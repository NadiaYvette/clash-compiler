{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE MagicHash             #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}

module CLaSH.Sized.Internal.Signed
  ( -- * Datatypes
    Signed (..)
    -- * Type classes
    -- ** Bits
  , pack#
  , unpack#
    -- Eq
  , eq#
  , neq#
    -- ** Ord
  , lt#
  , ge#
  , gt#
  , le#
    -- ** Enum (not synthesisable)
  , enumFrom#
  , enumFromThen#
  , enumFromTo#
  , enumFromThenTo#
    -- ** Bounded
  , minBound#
  , maxBound#
    -- ** Num
  , (+#)
  , (-#)
  , (*#)
  , negate#
  , abs#
  , fromInteger#
    -- ** Add
  , plus#
  , minus#
    -- ** Mult
  , mult#
    -- ** Integral
  , quot#
  , rem#
  , div#
  , mod#
  , quotRem#
  , divMod#
  , toInteger#
    -- ** Bitwise
  , and#
  , or#
  , xor#
  , complement#
  , shiftL#
  , shiftR#
  , rotateL#
  , rotateR#
    -- ** Resize
  , resize#
  , resize_wrap
    -- ** SaturatingNum
  , satPlus#
  , satMin#
  , satMult#
  , minBoundSym#
  )
where

import qualified Data.Bits            as B
import Data.Default                   (Default (..))
import Data.Proxy                     (Proxy (..))
import Data.Typeable                  (Typeable)
import GHC.TypeLits                   (KnownNat, Nat, type (+), natVal)
import Language.Haskell.TH            (TypeQ, appT, conT, litT, numTyLit, sigE)
import Language.Haskell.TH.Syntax     (Lift(..))

import CLaSH.Class.Bits               (Bits (..))
import CLaSH.Class.Bitwise            (Bitwise (..))
import CLaSH.Class.Num                (Add (..), Mult (..), SaturatingNum (..),
                                       SaturationMode (..))
import CLaSH.Class.Resize             (Resize (..))
import CLaSH.Prelude.BitIndex         (msb,split)
import CLaSH.Prelude.BitReduction     (reduceAnd, reduceOr)
import CLaSH.Promoted.Ord             (Max)
import CLaSH.Sized.Internal.BitVector (BitVector (..), (#>))


-- | Arbitrary-width signed integer represented by @n@ bits, including the sign
-- bit.
--
-- Uses standard 2-complements representation. Meaning that, given @n@ bits,
-- a 'Signed' @n@ number has a range of: [-(2^(@n@-1)) .. 2^(@n@-1)-1]
--
-- __NB__: The 'Num' operators perform @wrap-around@ on overflow. If you want
-- saturation on overflow, check out the 'CLaSH.Sized.Fixed.satN2' function in
-- "CLaSH.Sized.Fixed".
newtype Signed (n :: Nat) =
    -- | The constructor, 'S', and the field, 'unsafeToInteger', are not
    -- synthesisable.
    S { unsafeToInteger :: Integer}
  deriving Typeable

instance Show (Signed n) where
  show (S n) = show n

instance KnownNat n => Bits (Signed n) where
  type BitSize (Signed n) = n
  pack   = pack#
  unpack = unpack#

{-# NOINLINE pack# #-}
pack# :: KnownNat n => Signed n -> BitVector n
pack# s@(S i) = BV (i `mod` maxI)
  where
    maxI = 2 ^ natVal s

{-# NOINLINE unpack# #-}
unpack# :: KnownNat n => BitVector n -> Signed n
unpack# (BV i) = fromIntegerProxy_INLINE Proxy i

instance Eq (Signed n) where
  (==) = eq#
  (/=) = neq#

{-# NOINLINE eq# #-}
eq# :: Signed n -> Signed n -> Bool
eq# (S v1) (S v2) = v1 == v2

{-# NOINLINE neq# #-}
neq# :: Signed n -> Signed n -> Bool
neq# (S v1) (S v2) = v1 /= v2

instance Ord (Signed n) where
  (<)  = lt#
  (>=) = ge#
  (>)  = gt#
  (<=) = le#

lt#,ge#,gt#,le# :: Signed n -> Signed n -> Bool
{-# NOINLINE lt# #-}
lt# (S n) (S m) = n < m
{-# NOINLINE ge# #-}
ge# (S n) (S m) = n >= m
{-# NOINLINE gt# #-}
gt# (S n) (S m) = n > m
{-# NOINLINE le# #-}
le# (S n) (S m) = n <= m

-- | The functions: 'enumFrom', 'enumFromThen', 'enumFromTo', and
-- 'enumFromThenTo', are not synthesisable.
instance KnownNat n => Enum (Signed n) where
  succ           = (+# fromInteger# 1)
  pred           = (-# fromInteger# 1)
  toEnum         = fromInteger# . toInteger
  fromEnum       = fromEnum . toInteger#
  enumFrom       = enumFrom#
  enumFromThen   = enumFromThen#
  enumFromTo     = enumFromTo#
  enumFromThenTo = enumFromThenTo#

{-# NOINLINE enumFrom# #-}
{-# NOINLINE enumFromThen# #-}
{-# NOINLINE enumFromTo# #-}
{-# NOINLINE enumFromThenTo# #-}
enumFrom#       :: KnownNat n => Signed n -> [Signed n]
enumFromThen#   :: KnownNat n => Signed n -> Signed n -> [Signed n]
enumFromTo#     :: KnownNat n => Signed n -> Signed n -> [Signed n]
enumFromThenTo# :: KnownNat n => Signed n -> Signed n -> Signed n -> [Signed n]
enumFrom# x             = map toEnum [fromEnum x ..]
enumFromThen# x y       = map toEnum [fromEnum x, fromEnum y ..]
enumFromTo# x y         = map toEnum [fromEnum x .. fromEnum y]
enumFromThenTo# x1 x2 y = map toEnum [fromEnum x1, fromEnum x2 .. fromEnum y]


instance KnownNat n => Bounded (Signed n) where
  minBound = minBound#
  maxBound = maxBound#

minBound#,maxBound# :: KnownNat n => Signed n
{-# NOINLINE minBound# #-}
minBound# = let res = S $ negate $ 2 ^ (natVal res - 1) in res
{-# NOINLINE maxBound# #-}
maxBound# = let res = S $ 2 ^ (natVal res - 1) - 1 in res

-- | Operators do @wrap-around@ on overflow
instance KnownNat n => Num (Signed n) where
  (+)         = (+#)
  (-)         = (-#)
  (*)         = (*#)
  negate      = negate#
  abs         = abs#
  signum s    = if s < 0 then (-1) else
                   if s > 0 then 1 else 0
  fromInteger = fromInteger#

(+#), (-#), (*#) :: KnownNat n => Signed n -> Signed n -> Signed n
{-# NOINLINE (+#) #-}
(S a) +# (S b) = fromIntegerProxy_INLINE Proxy (a + b)

{-# NOINLINE (-#) #-}
(S a) -# (S b) = fromIntegerProxy_INLINE Proxy (a - b)

{-# NOINLINE (*#) #-}
(S a) *# (S b) = fromIntegerProxy_INLINE Proxy (a * b)

negate#,abs# :: KnownNat n => Signed n -> Signed n
{-# NOINLINE negate# #-}
negate# (S n) = fromIntegerProxy_INLINE Proxy (negate n)

{-# NOINLINE abs# #-}
abs# (S n) = fromIntegerProxy_INLINE Proxy (abs n)

{-# NOINLINE fromInteger# #-}
fromInteger# :: KnownNat n => Integer -> Signed (n :: Nat)
fromInteger# = fromIntegerProxy_INLINE Proxy

{-# INLINE fromIntegerProxy_INLINE #-}
fromIntegerProxy_INLINE :: KnownNat n => proxy n -> Integer -> Signed (n :: Nat)
fromIntegerProxy_INLINE p i = fromInteger_INLINE i (natVal p)

{-# INLINE fromInteger_INLINE #-}
fromInteger_INLINE :: Integer -> Integer -> Signed (n :: Nat)
fromInteger_INLINE i n
    | n == 0    = S 0
    | otherwise = res
  where
    sz  = 2 ^ (n - 1)
    res = case divMod i sz of
            (s,i') | even s    -> S i'
                   | otherwise -> S (i' - sz)

instance KnownNat (1 + Max m n) => Add (Signed m) (Signed n) where
  type AResult (Signed m) (Signed n) = Signed (1 + Max m n)
  plus  = plus#
  minus = minus#

plus#, minus# :: KnownNat (1 + Max m n) => Signed m -> Signed n
              -> Signed (1 + Max m n)
{-# NOINLINE plus# #-}
plus# (S a) (S b) = fromIntegerProxy_INLINE Proxy (a + b)

{-# NOINLINE minus# #-}
minus# (S a) (S b) = fromIntegerProxy_INLINE Proxy (a - b)

instance KnownNat (m + n) => Mult (Signed m) (Signed n) where
  type MResult (Signed m) (Signed n) = Signed (m + n)
  mult = mult#

{-# NOINLINE mult# #-}
mult# :: KnownNat (m + n) => Signed m -> Signed n -> Signed (m + n)
mult# (S a) (S b) = fromIntegerProxy_INLINE Proxy (a * b)

instance KnownNat n => Real (Signed n) where
  toRational = toRational . toInteger#

instance KnownNat n => Integral (Signed n) where
  quot      = quot#
  rem       = rem#
  div       = div#
  mod       = mod#
  quotRem   = quotRem#
  divMod    = divMod#
  toInteger = toInteger#

quot#,rem#,div#,mod# :: KnownNat n => Signed n -> Signed n -> Signed n
{-# NOINLINE quot# #-}
quot# = (fst.) . quotRem_INLINE
{-# NOINLINE rem# #-}
rem# = (snd.) . quotRem_INLINE
{-# NOINLINE div# #-}
div# = (fst.) . divMod_INLINE
{-# NOINLINE mod# #-}
mod# = (snd.) . divMod_INLINE

quotRem#,divMod# :: KnownNat n => Signed n -> Signed n -> (Signed n, Signed n)
quotRem# n d = (n `quot#` d,n `rem#` d)
divMod# n d  = (n `div#` d,n `mod#` d)

quotRem_INLINE,divMod_INLINE :: KnownNat n => Signed n -> Signed n
                             -> (Signed n, Signed n)
{-# INLINE quotRem_INLINE #-}
(S a) `quotRem_INLINE` (S b) = let (a',b') = a `quotRem` b
                               in ( fromIntegerProxy_INLINE Proxy a'
                                  , fromIntegerProxy_INLINE Proxy b')
{-# INLINE divMod_INLINE #-}
(S a) `divMod_INLINE` (S b) = let (a',b') = a `divMod` b
                              in ( fromIntegerProxy_INLINE Proxy a'
                                 , fromIntegerProxy_INLINE Proxy b')

{-# NOINLINE toInteger# #-}
toInteger# :: Signed n -> Integer
toInteger# (S n) = n

instance KnownNat n => Bitwise (Signed n) where
  (.&.)       = and#
  (.|.)       = or#
  xor         = xor#
  complement  = complement#
  shiftL v i  = shiftL#  v (fromIntegral i)
  shiftR v i  = shiftR#  v (fromIntegral i)
  rotateL v i = rotateL# v (fromIntegral i)
  rotateR v i = rotateR# v (fromIntegral i)

and#,or#,xor# :: KnownNat n => Signed n -> Signed n -> Signed n
{-# NOINLINE and# #-}
(S a) `and#` (S b) = fromIntegerProxy_INLINE Proxy (a B..&. b)
{-# NOINLINE or# #-}
(S a) `or#` (S b)  = fromIntegerProxy_INLINE Proxy (a B..|. b)
{-# NOINLINE xor# #-}
(S a) `xor#` (S b) = fromIntegerProxy_INLINE Proxy (B.xor a b)

{-# NOINLINE complement# #-}
complement# :: KnownNat n => Signed n -> Signed n
complement# = unpack# . complement . pack#

shiftL#,shiftR#,rotateL#,rotateR# :: KnownNat n => Signed n -> Int -> Signed n
{-# NOINLINE shiftL# #-}
shiftL# _ b | b < 0  = error "'shiftL undefined for negative numbers"
shiftL# (S n) b      = fromIntegerProxy_INLINE Proxy (B.shiftL n b)
{-# NOINLINE shiftR# #-}
shiftR# _ b | b < 0  = error "'shiftR undefined for negative numbers"
shiftR# (S n) b      = fromIntegerProxy_INLINE Proxy (B.shiftR n b)
{-# NOINLINE rotateL# #-}
rotateL# _ b | b < 0 = error "'shiftL undefined for negative numbers"
rotateL# s@(S n) b   = fromIntegerProxy_INLINE Proxy (l B..|. r)
  where
    l    = B.shiftL n b'
    r    = B.shiftR n b'' B..&. mask
    mask = 2 ^ b' - 1

    b'   = b `mod` sz
    b''  = sz - b'
    sz   = fromInteger (natVal s)

{-# NOINLINE rotateR# #-}
rotateR# _ b | b < 0 = error "'shiftR undefined for negative numbers"
rotateR# s@(S n) b   = fromIntegerProxy_INLINE Proxy (l B..|. r)
  where
    l    = B.shiftR n b' B..&. mask
    r    = B.shiftL n b''
    mask = 2 ^ b'' - 1

    b'  = b `mod` sz
    b'' = sz - b'
    sz  = fromInteger (natVal s)

-- | A sign-preserving resize operation
--
-- Increasing the size of the number replicates the sign bit to the left.
-- Truncating a number to length L keeps the sign bit and the rightmost L-1
-- bits.
instance Resize Signed where
  resize = resize#

{-# NOINLINE resize# #-}
resize# :: (KnownNat n, KnownNat m) => Signed n -> Signed m
resize# s@(S i) | n <= m    = extend
                | otherwise = trunc
  where
    n = fromInteger (natVal s)
    m = fromInteger (natVal extend)

    extend = fromIntegerProxy_INLINE Proxy i

    mask  = (2 ^ (m - 1)) - 1
    sign  = 2 ^ (m - 1)
    i'    = i B..&. mask
    trunc = if B.testBit i (n - 1)
               then fromIntegerProxy_INLINE Proxy (i' B..|. sign)
               else fromIntegerProxy_INLINE Proxy i'

{-# NOINLINE resize_wrap #-}
-- | A resize operation that is sign-preserving on extension, but wraps on
-- truncation.
--
-- Increasing the size of the number replicates the sign bit to the left.
-- Truncating a number of length N to a length L just removes the leftmost
-- N-L bits.
resize_wrap :: KnownNat m => Signed n -> Signed m
resize_wrap (S n) = fromIntegerProxy_INLINE Proxy n

instance KnownNat n => Default (Signed n) where
  def = fromInteger# 0

instance KnownNat n => Lift (Signed n) where
  lift s@(S i) = sigE [| fromInteger# i |] (decSigned (natVal s))

decSigned :: Integer -> TypeQ
decSigned n = appT (conT ''Signed) (litT $ numTyLit n)

instance (KnownNat n, KnownNat (1 + n), KnownNat (n + n)) =>
  SaturatingNum (Signed n) where
  satPlus = satPlus#
  satMin  = satMin#
  satMult = satMult#

satPlus#, satMin# :: (KnownNat n, KnownNat (1 + n)) => SaturationMode
                  -> Signed n -> Signed n -> Signed n

satPlus# SatWrap a b = a +# b
satPlus# w a b = case msb r `xor` msb r' of
                   0 -> unpack# r'
                   _ -> case msb a .&. msb b of
                          1 -> case w of
                                 SatBound     -> minBound#
                                 SatSymmetric -> minBoundSym#
                                 _            -> fromInteger# 0
                          _ -> case w of
                                 SatZero -> fromInteger# 0
                                 _       -> maxBound#
  where
    r      = plus# a b
    (_,r') = split r

satMin# SatWrap a b = a -# b
satMin# w a b = case msb r `xor` msb r' of
                   0 -> unpack# r'
                   _ -> case msb a #> msb b of
                          2 -> case w of
                                 SatBound     -> minBound#
                                 SatSymmetric -> minBoundSym#
                                 _            -> fromInteger# 0
                          _ -> case w of
                                 SatZero -> fromInteger# 0
                                 _       -> maxBound#
  where
    r      = minus# a b
    (_,r') = split r

satMult# :: (KnownNat n, KnownNat (1 + n), KnownNat (n + n)) => SaturationMode
         -> Signed n -> Signed n -> Signed n
satMult# SatWrap a b = a *# b
satMult# w a b = case overflow of
                   1 -> unpack# rR
                   _ -> case msb rL of
                          0 -> case w of
                                 SatZero -> fromInteger# 0
                                 _       -> maxBound#
                          _ -> case w of
                                 SatBound     -> minBound#
                                 SatSymmetric -> minBoundSym#
                                 _            -> fromInteger# 0
  where
    overflow = complement (reduceOr (msb rR #> pack rL)) .|.
                          reduceAnd (msb rR #> pack rL)
    r        = mult# a b
    (rL,rR)  = split r

{-# NOINLINE minBoundSym# #-}
minBoundSym# :: KnownNat n => Signed n
minBoundSym# = let res = S $ negate $ 2 ^ (natVal res - 1) - 1 in res
