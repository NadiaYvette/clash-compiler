{-|
Copyright  :  (C) 2018, Google Inc.
License    :  BSD2 (see the file LICENSE)
Maintainer :  Christiaan Baaij <christiaan.baaij@gmail.com>

Using /ANN/ pragma's you can tell the Clash compiler to use a custom
bit-representation for a data type. See @DataReprAnn@ for documentation.

-}

{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DeriveLift         #-}
{-# LANGUAGE RankNTypes         #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell    #-}

{-# OPTIONS_GHC -Wno-orphans #-}

module Clash.Annotations.BitRepresentation
 (
 -- * Data structures to express a custom bit representation
   DataReprAnn(..)
 , ConstrRepr(..)
 -- * Convenience type synonyms for Integer
 , BitMask
 , Value
 , Size
 , FieldAnn

 -- * Functions
 , reprType
 ) where

import           Data.Data                  (Data)
import           Data.Typeable              (Typeable)
import qualified Language.Haskell.TH.Lib    as TH
import qualified Language.Haskell.TH.Lift   ()
import qualified Language.Haskell.TH.Syntax as TH

type BitMask  = Integer
type Value    = Integer
type Size     = Integer

type FieldAnn = BitMask

reprType :: TH.TypeQ -> TH.ExpQ
reprType qty = qty >>= TH.lift

deriving instance TH.Lift TH.Type
deriving instance TH.Lift TH.TyVarBndr
deriving instance TH.Lift TH.TyLit

-- NOTE: The following instances are imported from Language.Haskell.TH.Lift.
-- This module also implements 'instance Lift Exp', which might make debugging
-- template haskell more difficult. Please uncomment these instances and the
-- import of TH.Lift whenever it suits you.
--
--deriving instance TH.Lift TH.Name
--deriving instance TH.Lift TH.OccName
--deriving instance TH.Lift TH.NameFlavour
--deriving instance TH.Lift TH.ModName
--deriving instance TH.Lift TH.NameSpace
--deriving instance TH.Lift TH.PkgName


-- | Annotation for custom bit representations of data types
--
-- Using /ANN/ pragma's you can tell the Clash compiler to use a custom
-- bit-representation for a data type.
--
-- For example:
--
-- @
-- data Color = R | G | B
-- {-# ANN module (DataReprAnn
--                   $(reprType [t|Color|])
--                   2
--                   [ ConstrRepr 'R 0b11 0b00 []
--                   , ConstrRepr 'G 0b11 0b01 []
--                   , ConstrRepr 'B 0b11 0b10 []
--                   ]) #-}
-- @
--
-- This specifies that @R@ should be encoded as 0b00, @G@ as 0b01, and
-- @B@ as 0b10. The first binary value in every @ConstRepr@ in this example
-- is a mask, indicating which bits in the data type are relevant. In this case
-- all of the bits are.
--
-- Or if we want to annotate @Maybe Color@:
--
-- @
-- {-# ANN module ( DataReprAnn
--                    $(reprType [t|Maybe Color|])
--                    2
--                    [ ConstRepr 'Nothing 0b11 0b11 []
--                    , ConstRepr 'Just 0b00 0b00 [0b11]
--                    ] ) #-}
-- @
--
-- By default, @Maybe Color@ is a data type which consumes 3 bits. A single bit
-- to indicate the constructor (either @Just@ or @Nothing@), and two bits to encode
-- the first field of @Just@. Notice that we saved a single bit, by exploiting
-- the fact that @Color@ only uses three values (0, 1, 2), but takes two bits
-- to encode it. We can therefore use the last - unused - value (3), to encode
-- one of the constructors of @Maybe@. We indicate which bits encode the
-- underlying @Color@ by passing /[0b11]/ to ConstRepr. This indicates that the
-- first field is encoded in the first and second bit of the whole datatype (0b11).
data DataReprAnn =
  DataReprAnn
    -- Type this annotation is for:
    TH.Type
    -- Size of type:
    Size
    -- Constructors:
    [ConstrRepr]
      deriving (Show, Data, Typeable)

-- | Annotation for constructors. Indicates how to match this constructor based
-- off of the whole datatype.
data ConstrRepr =
  ConstrRepr
    -- Constructor name:
    TH.Name
    -- Bits relevant for this constructor:
    BitMask
    -- data & mask should be equal to..:
    Value
    -- Masks for fields. Indicates where fields are stored:
    [FieldAnn]
      deriving (Show, Data, Typeable)
