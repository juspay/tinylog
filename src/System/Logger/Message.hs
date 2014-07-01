-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}

-- | 'Msg' and 'ToBytes' assist in constructing log messages.
-- For example:
--
-- @
-- > g <- new defSettings { bufSize = 1, output = StdOut }
-- > info g $ msg "some text" ~~ "key" .= "value" ~~ "okay" .= True
-- 2014-04-28T21:18:20Z, I, some text, key=value, okay=True
-- >
-- @
module System.Logger.Message
    ( ToBytes (..)
    , Msg
    , msg
    , field
    , (.=)
    , (+++)
    , (~~)
    , val
    , render
    ) where

import Data.ByteString (ByteString)
import Data.ByteString.Lazy.Builder (Builder)
import Data.Int
import Data.List (intersperse)
import Data.Monoid
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import Data.Word

import qualified Data.ByteString                     as S
import qualified Data.ByteString.Lazy                as L
import qualified Data.ByteString.Lazy.Builder        as B
import qualified Data.ByteString.Lazy.Builder.Extras as B
import qualified Data.Text.Lazy                      as T
import qualified Data.Text.Lazy.Encoding             as T

-- | Convert some value to a 'Builder'.
class ToBytes a where
    bytes :: a -> Builder

instance ToBytes Builder      where bytes = id
instance ToBytes L.ByteString where bytes = B.lazyByteString
instance ToBytes ByteString   where bytes = B.byteString
instance ToBytes Char         where bytes = B.charUtf8
instance ToBytes Int          where bytes = B.intDec
instance ToBytes Int8         where bytes = B.int8Dec
instance ToBytes Int16        where bytes = B.int16Dec
instance ToBytes Int32        where bytes = B.int32Dec
instance ToBytes Int64        where bytes = B.int64Dec
instance ToBytes Integer      where bytes = B.integerDec
instance ToBytes Word         where bytes = B.wordDec
instance ToBytes Word8        where bytes = B.word8Dec
instance ToBytes Word16       where bytes = B.word16Dec
instance ToBytes Word32       where bytes = B.word32Dec
instance ToBytes Word64       where bytes = B.word64Dec
instance ToBytes Float        where bytes = B.floatDec
instance ToBytes Double       where bytes = B.doubleDec
instance ToBytes Text         where bytes = B.byteString . encodeUtf8
instance ToBytes T.Text       where bytes = B.lazyByteString . T.encodeUtf8
instance ToBytes [Char]       where bytes = B.stringUtf8

instance ToBytes Bool where
    bytes True  = val "True"
    bytes False = val "False"

-- | Type representing log messages.
newtype Msg = Msg { elements :: [Element] }

data Element
    = Bytes L.ByteString
    | Field ByteString L.ByteString

-- | Turn some value into a 'Msg'.
msg :: ToBytes a => a -> Msg -> Msg
msg p (Msg m) = Msg $ Bytes (lbstr p) : m

-- | Render some field, i.e. a key-value pair delimited by \"=\".
field :: ToBytes a => ByteString -> a -> Msg -> Msg
field k v (Msg m) = Msg $ Field k (lbstr v) : m

-- | Alias of 'field'.
(.=) :: ToBytes a => ByteString -> a -> Msg -> Msg
(.=) = field
infixr 5 .=

-- | Alias of '.' with lowered precedence to allow combination with '.='
-- without requiring parentheses.
(~~) :: (b -> c) -> (a -> b) -> a -> c
(~~) = (.)
infixr 4 ~~

-- | Concatenate two 'ToBytes' values.
(+++) :: (ToBytes a, ToBytes b) => a -> b -> Builder
a +++ b = bytes a <> bytes b
infixr 6 +++

-- | Type restriction. Useful to disambiguate string literals when
-- using @OverloadedStrings@ pragma.
val :: ByteString -> Builder
val = bytes

-- | Intersperse parts of the log message with the given delimiter and
-- render the whole builder into a 'L.ByteString'.
--
-- If the second parameter is set to @True@, netstrings encoding is used for
-- the message elements. Cf. <http://cr.yp.to/proto/netstrings.txt> for
-- details.
render :: ByteString -> Bool -> (Msg -> Msg) -> L.ByteString
render _ True m = finish . mconcat . map enc . elements . m $ empty
  where
    enc (Bytes   e) = netstrLB e
    enc (Field k v) = netstrSB k <> eq <> netstrLB v
    eq              = val "1:=,"

render s False m = finish . mconcat . seps . map enc . elements . m $ empty
  where
    enc (Bytes   e) = bytes e
    enc (Field k v) = k +++ val "=" +++ v
    seps            = intersperse (bytes s)

finish :: Builder -> L.ByteString
finish = B.toLazyByteStringWith (B.untrimmedStrategy 256 256) "\n"

empty :: Msg
empty = Msg []

netstrSB :: ByteString -> Builder
netstrSB b = S.length b +++ val ":" +++ b +++ val ","

netstrLB :: L.ByteString -> Builder
netstrLB b = L.length b +++ val ":" +++ b +++ val ","

lbstr :: ToBytes a => a -> L.ByteString
lbstr = B.toLazyByteStringWith (B.untrimmedStrategy 64 64) L.empty . bytes

