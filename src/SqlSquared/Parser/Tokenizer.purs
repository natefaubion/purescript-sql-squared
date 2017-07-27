module SqlSquared.Parser.Tokenizer
  ( tokenize
  , Token(..)
  , Literal(..)
  ) where

import Prelude

import Control.Alt ((<|>))
import Data.Array as A
import Data.Either (Either)
import Data.HugeInt as HI
import Data.HugeNum as HN
import Data.Json.Extended.Signature.Parse as EJP
import Data.Set as Set
import Data.String as S
import SqlSquared.Utils ((∘))
import Text.Parsing.Parser as P
import Text.Parsing.Parser.Combinators as PC
import Text.Parsing.Parser.String as PS
import Text.Parsing.Parser.Token as PT

data Literal
  = String String
  | Integer HI.HugeInt
  | Decimal HN.HugeNum

derive instance eqTokenLit ∷ Eq Literal

data Token
  = Kw String
  | Op String
  | Identifier String
  | Lit Literal
  | Comment String

isKeyword ∷ Token → Boolean
isKeyword = case _ of
  Kw _ → true
  _ → false

isComment ∷ Token → Boolean
isComment = case _ of
  Comment _ → true
  _ → false

derive instance eqToken ∷ Eq Token


op ∷ ∀ m. Monad m ⇒ P.ParserT String m Token
op = map Op $ PC.choice
  [ PC.try $ PS.string "{*:}"
  , PC.try $ PS.string "{*}"
  , PC.try $ PS.string "{:*}"
  , PC.try $ PS.string "{_:}"
  , PC.try $ PS.string "{_}"
  , PC.try $ PS.string "[*:]"
  , PC.try $ PS.string "[*]"
  , PC.try $ PS.string "[:*]"
  , PC.try $ PS.string "[_]"
  , PC.try $ PS.string "..."
  , PC.try $ PS.string ".."
  , PC.try $ PS.string "<>"
  , PC.try $ PS.string "!="
  , PC.try $ PS.string "||"
  , PC.try $ PS.string "??"
  , PC.try $ PS.string "!~*"
  , PC.try $ PS.string "!~"
  , PC.try $ PS.string "!~~"
  , PC.try $ PS.string "~~"
  , PC.try $ PS.string "~*"
  , PC.try $ PS.string ":="
  , PS.string "~"
  , PS.string "??"
  , PS.string "="
  , PS.string ">"
  , PS.string "<"
  , PS.string "["
  , PS.string "]"
  , PS.string ":"
  , PS.string ","
  , PS.string ";"
  , PS.string "*"
  , PS.string "("
  , PS.string ")"
  , PS.string "{"
  , PS.string "}"
  , PS.string "-"
  , PS.string "+"
  , PS.string "^"
  , PS.string "."
  , PS.string "/"
  , PS.string "%"
  ]

keywords ∷ Set.Set String
keywords = Set.fromFoldable
  [ "where"
  , "when"
  , "values"
  , "union"
  , "true"
  , "then"
  , "select"
  , "sample"
  , "right"
  , "outer"
  , "order"
  , "or"
  , "on"
  , "offset"
  , "null"
  , "not"
  , "limit"
  , "like"
  , "left"
  , "join"
  , "is"
  , "into"
  , "intersect"
  , "insert"
  , "inner"
  , "in"
  , "import"
  , "having"
  , "group"
  , "function"
  , "full"
  , "from"
  , "false"
  , "exists"
  , "except"
  , "escape"
  , "end"
  , "else"
  , "distinct"
  , "desc"
  , "delete"
  , "cross"
  , "create"
  , "case"
  , "by"
  , "between"
  , "begin"
  , "asc"
  , "as"
  , "and"
  , "all"
  ]

digits ∷ Array Char
digits = ['0','1','2','3','4','5','6','7','8','9' ]

identOrKeyword ∷ ∀ m. Monad m ⇒ P.ParserT String m Token
identOrKeyword = PC.try quotedIdent <|> notQuotedIdentOrKeyword

oneLineComment ∷ ∀ m. Monad m ⇒ P.ParserT String m Token
oneLineComment =
  PC.between (PC.try $ PS.string "--") (PS.string "\n")
    $ map (Comment ∘ S.fromCharArray)
    $ A.many $ PS.satisfy
    $ not ∘ eq '\n'

multiLineComment ∷ ∀ m. Monad m ⇒ P.ParserT String m Token
multiLineComment = do
  _ ← PS.string "/*"
  m ← collectBeforeComment ""
  pure $ Comment m
  where
  collectBeforeComment acc =
    let l = S.length acc
    in do
      c ← PS.anyChar
      case S.drop (l - 1) acc of
        "*" | c == '/' →
          pure acc
        _ →
          collectBeforeComment $ acc <> S.fromCharArray [ c ]

quotedIdent ∷ ∀ m. Monad m ⇒ P.ParserT String m Token
quotedIdent =
  map Identifier
    $ PC.between (PS.string "`") (PS.string "`")
    $ map S.fromCharArray
    $ A.some identChar
  where
  identChar = PC.try identEscape <|> identLetter
  identLetter = PS.satisfy (not ∘ eq '`')
  identEscape = PS.string "\\`" $> '`'

notQuotedIdentOrKeyword ∷ ∀ m. Monad m ⇒ P.ParserT String m Token
notQuotedIdentOrKeyword = do
  first ← PT.letter
  other ← A.many (PT.alphaNum <|> PS.char '_')
  let
    str = S.fromCharArray $ A.cons first other
    low = S.toLower str
  pure if Set.member low keywords
    then Kw low
    else Identifier str

stringLit ∷ ∀ m. Monad m ⇒ P.ParserT String m Token
stringLit = Lit ∘ String <$> EJP.parseStringLiteral

numLit ∷ ∀ m. Monad m ⇒ P.ParserT String m Token
numLit = Lit ∘ Decimal <$> EJP.parseDecimalLiteral

intLit ∷ ∀ m. Monad m ⇒ P.ParserT String m Token
intLit = Lit ∘ Integer <$> EJP.parseHugeIntLiteral

tokens ∷ ∀ m. Monad m ⇒ P.ParserT String m (Array Token)
tokens = do
  PS.skipSpaces
  A.some $ PC.choice
    [ skipped oneLineComment
    , skipped multiLineComment
    , skipped op
    , skipped identOrKeyword
    , skipped numLit
    , skipped intLit
    , skipped stringLit
    ]
  where
  skipped r = PC.try (r <* PS.skipSpaces)

tokenize ∷ String → Either P.ParseError (Array Token)
tokenize input =
  A.filter (not ∘ isComment) <$>  P.runParser input tokens
