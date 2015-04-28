{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections     #-}
module CLaSH.Driver.TopWrapper where

import           Data.Aeson           (FromJSON (..), Value (..), (.:))
import           Data.Aeson.Extra     (decodeAndReport)
import qualified Data.ByteString.Lazy as B
import qualified Data.HashMap.Strict  as H
import           Data.List            (mapAccumL)
import           Data.Text.Lazy       (Text, append, pack)
import           System.Directory     (doesFileExist)

import CLaSH.Netlist.Types (Component (..), Declaration (..), Expr (..), Identifier, HWType (..), Modifier (..))
import CLaSH.Util

data TopEntity
  = TopEntity
  { t_name    :: Text
  , t_inputs  :: [Text]
  , t_outputs :: [Text]
  }
  deriving Show

instance FromJSON TopEntity where
  parseJSON (Object v) = case H.toList v of
    [(conKey,Object conVal)] -> case conKey of
      "TopEntity"  -> TopEntity <$> conVal .: "name" <*> (conVal .: "inputs") <*> (conVal .: "outputs")
      _ -> error "Expected: TopEntity"
    _ -> error "Expected: TopEntity object"
  parseJSON _ = error "Expected: TopEntity object"

mkTopWrapper :: Maybe TopEntity -> Component -> Component
mkTopWrapper teM topComponent
  = topComponent
  { componentName = maybe "topEntity" t_name teM
  , inputs        = inputs''
  , outputs       = outputs''
  , declarations  = wrappers ++ instDecl:unwrappers
  }
  where
    iNameSupply                = maybe [] t_inputs teM
    inputs'                    = map (first (const "input"))
                                     (inputs topComponent)
    (inputs'',(wrappers,idsI)) = (concat *** (first concat . unzip))
                               . unzip
                               . snd
                               $ mapAccumL (\nm (i,c) -> mkInput nm i c)
                                            iNameSupply
                                            (zip inputs' [0..])

    oNameSupply                   = maybe [] t_outputs teM
    outputs'                      = map (first (const "output"))
                                        (outputs topComponent)
    (outputs'',(unwrappers,idsO)) = (concat *** (first concat . unzip))
                                  . unzip
                                  . snd
                                  $ mapAccumL (\nm (o,c) -> mkOutput nm o c)
                                              oNameSupply
                                              (zip outputs' [0..])

    instDecl = InstDecl (componentName topComponent)
                        (append (componentName topComponent) (pack "_inst"))
                        (zipWith (\(p,_) i -> (p,Identifier i Nothing))
                                 (inputs topComponent)
                                 idsI
                         ++
                         map (\(p,_) -> (p,Identifier p Nothing))
                             (hiddenPorts topComponent)
                         ++
                         zipWith (\(p,_) i -> (p,Identifier i Nothing))
                                 (outputs topComponent)
                                 idsO)

mkInput :: [Identifier]
        -> (Identifier,HWType)
        -> Int
        -> ( [Identifier]
           , ( [(Identifier,HWType)]
             , ( [Declaration]
               , Identifier
               )
             )
           )
mkInput nms (i,hwty) cnt = case hwty of
  Vector sz hwty' ->
    let (nms',(ports',(decls',ids))) = second ( (concat *** (first concat . unzip))
                                              . unzip
                                              )
                                     $ mapAccumL
                                        (\nm c -> mkInput nm (iName,hwty') c)
                                        nms [0..(sz-1)]
        netdecl  = NetDecl iName hwty
        netassgn = Assignment iName (mkVectorChain sz hwty' ids)
    in  (nms',(ports',(netdecl:decls' ++ [netassgn],iName)))
  Product _ hwtys ->
    let (nms',(ports',(decls',ids))) = second ( (concat *** (first concat . unzip))
                                              . unzip
                                              )
                                     $ mapAccumL
                                        (\nm (inp,c) -> mkInput nm inp c)
                                        nms (zip (map (iName,) hwtys) [0..])
        netdecl  = NetDecl iName hwty
        ids'     = map (`Identifier` Nothing) ids
        netassgn = Assignment iName (DataCon hwty (DC (hwty,0)) ids')
    in  (nms',(ports',(netdecl:decls' ++ [netassgn],iName)))
  _ -> case nms of
         []       -> (nms,([(iName,hwty)],([],iName)))
         (n:nms') -> (nms',([(n,hwty)],([],n)))
  where

    iName = append i (pack ("_" ++ show cnt))

mkVectorChain :: Int
              -> HWType
              -> [Identifier]
              -> Expr
mkVectorChain _ elTy []      = DataCon (Vector 0 elTy) VecAppend []
mkVectorChain _ elTy [i]     = DataCon (Vector 1 elTy) VecAppend
                                [Identifier i Nothing]
mkVectorChain sz elTy (i:is) = DataCon (Vector sz elTy) VecAppend
                                [ Identifier i Nothing
                                , mkVectorChain (sz-1) elTy is
                                ]

mkOutput :: [Identifier]
         -> (Identifier,HWType)
         -> Int
         -> ( [Identifier]
            , ( [(Identifier,HWType)]
              , ( [Declaration]
                , Identifier
                )
              )
            )
mkOutput nms (i,hwty) cnt = case hwty of
  Vector sz hwty' ->
    let (nms',(ports',(decls',ids))) = second ( (concat *** (first concat . unzip))
                                              . unzip
                                              )
                                     $ mapAccumL
                                        (\nm c -> mkOutput nm (iName,hwty') c)
                                        nms [0..(sz-1)]
        netdecl  = NetDecl iName hwty
        assigns  = zipWith
                     (\id_ n -> Assignment id_
                                  (Identifier iName (Just (Indexed (hwty,1,n)))))
                     ids
                     [0..]
    in  (nms',(ports',(netdecl:assigns ++ decls',iName)))
  Product _ hwtys ->
    let (nms',(ports',(decls',ids))) = second ( (concat *** (first concat . unzip))
                                              . unzip
                                              )
                                     $ mapAccumL
                                        (\nm (inp,c) -> mkOutput nm inp c)
                                        nms (zip (map (iName,) hwtys) [0..])
        netdecl  = NetDecl iName hwty
        assigns  = zipWith
                     (\id_ n -> Assignment id_
                                  (Identifier iName (Just (Indexed (hwty,0,n)))))
                     ids
                     [0..]
    in  (nms',(ports',(netdecl:assigns ++ decls',iName)))
  _ -> case nms of
         []       -> (nms,([(iName,hwty)],([],iName)))
         (n:nms') -> (nms',([(n,hwty)],([],n)))
  where
    iName = append i (pack ("_" ++ show cnt))

generateTopEnt :: String
               -> IO (Maybe TopEntity)
generateTopEnt modName = do
  let topEntityFile = modName ++ ".topentity"
  exists <- doesFileExist topEntityFile
  if exists
    then return . decodeAndReport <=< B.readFile $ topEntityFile
    else return Nothing
