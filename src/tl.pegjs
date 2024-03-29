{
  const makeNode = (type, body = {}) => ({
    type,
    ...location(),
    ...body,
  })

  const makeFinalDecl = (finalization, id) =>
    makeNode('FinalDeclaration', { finalization, id })

  const makeDeclarationsNode = (type, declarations, initial = []) =>
    makeNode(type, {
      declarations: declarations
        .filter(e => e.type === type)
        .reduce((acc, { declarations }) => {
          acc.push(...declarations)
          return acc
        }, initial)
    })

  // [[a,b],[c,d]] -> [a,c]
  const extractFirst = list =>
    list.map(list2 => list2 && list2[0])

  // [[a,b],[c,d]] -> [b,d]
  const extractLast = list =>
    list.map(list2 => list2 && list2[list2.length - 1])

  const safeFirst = list => list ? list[0] : null
  const safeLast = list => list ? list[list.length - 1] : null
}

Start
  = __ program:TLProgram __ { return program }

// ---Character classes---

LcLetter
  = letter:[a-z] { return letter }

UcLetter
  = letter:[A-Z] { return letter }

Digit
  = digit:[0-9] { return Number(digit) }

HexDigit
  = hexDigit:[0-9a-f] { return hexDigit }

Letter = LcLetter / UcLetter
IdentChar = Letter / Digit / "_"

// ---Simple identifiers and keywords---

LcIdent = LcLetter IdentChar* { return text() }
UcIdent = UcLetter IdentChar* { return text() }
NamespaceIdent = LcIdent
LcIdentNs = (NamespaceIdent ".")? LcIdent { return text() }
UcIdentNs = (NamespaceIdent ".")? UcIdent { return text() }
LcIdentFull =
  LcIdentNs ("#"
    // 4 - 8 hex digits
    HexDigit HexDigit HexDigit HexDigit
    HexDigit? HexDigit? HexDigit? HexDigit?
  )? { return text() }

// ---Other tokens---

FinalKw  = "Final"  !IdentChar
NewKw    = "New"    !IdentChar
EmptyKw  = "Empty"  !IdentChar

NatConst = Digit+ !IdentChar { return Number(text()) }

// ---General syntax of a TL program---

TLProgram
  = head:ConstrDeclarations tail:(
      __ "---" "functions" "---" __ FunDeclarations
      / __ "---" "types" "---" __ ConstrDeclarations
    )* {
      const declarations = extractLast(tail)
      const constructors = makeDeclarationsNode(
        'ConstructorDeclarations', declarations, head.declarations)
      const functions = makeDeclarationsNode(
        'FunctionDeclarations', declarations)
      return makeNode('TLProgram', {
        constructors,
        functions
      })
    }

ConstrDeclarations
  = decls:(Declaration __)*
    { return makeNode('ConstructorDeclarations', {
        declarations: extractFirst(decls) }) }

FunDeclarations
  = decls:(Declaration __)*
    { return makeNode('FunctionDeclarations', {
        declarations: extractFirst(decls) }) }

Declaration
  = FinalDecl
  / CombinatorDecl
  / BuiltinCombinatorDecl
  / PartialAppDecl

// ---Syntactical categories and constructions---

ENat
  = value:NatConst
    { return makeNode('ENat', { value }) }

// TypeExpr
//   = expression:Expr
//     { return makeNode('TypeExpression', { expression }) }
// NatExpr
//   = expression:Expr
//     { return makeNode('NatExpression', { expression }) }
Expr
  = subexprs:(__ Subexpr)* {
      return makeNode('EExpression', {
        subexpressions: extractLast(subexprs)
      })
    }
Subexpr
  = Term
  / natexpr:ENat __ "+" __ subexpr:Subexpr {
      return makeNode('EOperator', {
        kind: '+',
        expression: makeNode('EExpression', {
          subexpressions: [natexpr, subexpr]
        })
      })
    }
  // / Subexpr "+" NatConst
// Possible infinite loop when parsing
// (left recursion: Expr -> Subexpr -> Subexpr).

ETypeIdent
  = id:TypeIdent
    { return makeNode('ETypeIdentifier', { id }) }

Term
  = "(" __ expr:Expr __ ")" { return expr }
  // / id:ETypeIdent __ "<" __ head:Expr tail:(__ "," __ Expr)* __ ">" {
  / id:ETypeIdent __ "<" __ head:Subexpr tail:(__ "," __ Subexpr)* __ ">" {
      return makeNode('EExpression', {
        subexpressions: [id, head].concat(extractLast(tail))
      })
    }
  / ETypeIdent
  // / VarIdent //?
  / ENat
  / "%" terms:(__ Term)+ {
      const subexpressions = extractLast(terms)
      return makeNode('EOperator', {
        kind: '%',
        expression: subexpressions.length > 1
          ? makeNode('EExpression', { subexpressions })
          : subexpressions[0]
      })
    }

SimpleTypeIdent
  = name:LcIdentNs
    { return makeNode('SimpleTypeIdentifier', { name }) }
HashTypeIdent
  = name:"#"
    { return makeNode('HashTypeIdentifier', { name }) }

TypeIdent
  = BoxedTypeIdent / SimpleTypeIdent / HashTypeIdent
BoxedTypeIdent
  = name:UcIdentNs
    { return makeNode('BoxedTypeIdentifier', { name }) }
VarIdent
  = name:(LcIdent / UcIdent)
    { return makeNode('VariableIdentifier', { name }) }
TypeTerm
  = bang:"!"? __ expr:Term {
      const expression = bang === '!'
        ? makeNode('EOperator', { kind: '!', expression: expr })
        : expr
      return makeNode('TypeExpression', { expression })
    }
NatTerm
  = expression:Term
    { return makeNode('NatExpression', { expression }) }

// ---Combinator declarations---

FullCombName
  = ident:LcIdentFull {
      const [name, magic] = ident.split('#')
      if (!magic) return makeNode('ShortCombinatorName', { name })
      return makeNode('FullCombinatorName', { name, magic })
    }
ShortCombName
  = name:LcIdentNs
    { return makeNode('ShortCombinatorName', { name }) }
EmptyCombName
  = name:"_"
    { return makeNode('EmptyCombinatorName', { name }) }

VarIdentEmpty
  = name:"_"
    { return makeNode('EmptyVariableIdentifier', { name }) }

CombinatorDecl
  = id:FullCombinatorId __
    optionalArgs:(OptArgs __)*
    args:(Args __)*
    "=" __ excl:"!"? __
    resultType:ResultType __ ";" {
      return makeNode('CombinatorDeclaration', {
        id,
        optionalArgs: [].concat(...extractFirst(optionalArgs)),
        args: [].concat(...extractFirst(args)),
        bang: excl === "!",
        resultType
      })
    }
FullCombinatorId
  = FullCombName / EmptyCombName
CombinatorId
  = ShortCombName / EmptyCombName
OptArgs
  // = "{" ids:(__ VarIdent)+ __ ":" __ "!"? __ type:TypeExpr __ "}"
  = "{" ids:(__ VarIdent)+ __ ":" __ argType:TypeTerm __ "}" {
      return extractLast(ids).map(id =>
        makeNode('OptionalArgument', { id, argType }))
    }
Args
  = idOrNull:(VarIdentOpt __ ":")? __
    mult:(Multiplicity "*")? __
    "[" __ subargs:(__ Args)* __ "]" {
      const id = safeFirst(idOrNull)
        || makeNode('EmptyVariableIdentifier', { name: '_' })

      const argType = makeNode('TypeExpression', {
        expression: makeNode('EMultiArg', {
          multiplicity: safeFirst(mult),
          subargs: [].concat(...extractLast(subargs))
        })
      })

      return [makeNode('Argument', {
        id,
        conditionalDef: null,
        argType
      })]
    }
  / id:VarIdentOpt __ ":" __ cond:ConditionalDef? __ argType:TypeTerm
    { return [makeNode('Argument', { id, conditionalDef: cond, argType })] }
  / id:VarIdentOpt __ ":" __ "(" __ cond:ConditionalDef? __ argType:TypeTerm __ ")"
    { return [makeNode('Argument', { id, conditionalDef: cond, argType })] }
  / "(" ids:(__ VarIdentOpt)+ __ ":" __ argType:TypeTerm __ ")" {
      return extractLast(ids).map(id =>
        makeNode('Argument', { id, conditionalDef: null, argType }))
    }
  / argType:TypeTerm {
      return [makeNode('Argument', {
        id: makeNode('EmptyVariableIdentifier', { name: '_' }),
        conditionalDef: null,
        argType
      })]
    }
Multiplicity
  = NatTerm
VarIdentOpt
  = VarIdent / VarIdentEmpty
ConditionalDef
  = id:VarIdent __ nat:("." NatConst)? __ "?" {
      return makeNode('ConditionalDefinition', {
        id,
        nat: safeLast(nat)
      })
    }
ResultType
  = id:BoxedTypeIdent __ "<" __ head:Subexpr tail:(__ "," __ Subexpr)* __ ">" {
      return makeNode('ResultType', {
        id,
        expression: makeNode('EExpression', {
          subexpressions: [head].concat(extractLast(tail))
        })
      })
    }
  / id:BoxedTypeIdent subexprs:(__ Subexpr)* {
      return makeNode('ResultType', {
        id,
        expression: makeNode('EExpression', {
          subexpressions: extractLast(subexprs)
        })
      })
    }

BuiltinCombinatorDecl
  = id:FullCombinatorId __
    "?" __ "=" __
    result:BoxedTypeIdent __ ";"
    { return makeNode('BuiltinCombinatorDeclaration', { id, result }) }

// ---Partial applications (patterns)---

PartialAppDecl
  = PartialTypeAppDecl
  / PartialCombAppDecl
PartialTypeAppDecl
  // = id:BoxedTypeIdent __ "<" __ head:Expr tail:(__ "," __ Expr)* __ ">" __ ";" {
  = id:BoxedTypeIdent __ "<" __ head:Subexpr tail:(__ "," __ Subexpr)* __ ">" __ ";" {
      return makeNode('PartialTypeApplicationDeclaration', {
        id,
        expression: makeNode('EExpression', {
          subexpressions: [head].concat(extractLast(tail))
        })
      })
    }
  / id:BoxedTypeIdent subexprs:(__ Subexpr)+ __ ";" {
      return makeNode('PartialTypeApplicationDeclaration', {
        id,
        expression: makeNode('EExpression', {
          subexpressions: extractLast(subexprs)
        })
      })
    }
PartialCombAppDecl
  = id:CombinatorId subexprs:(__ Subexpr)+ __ ";" {
      return makeNode('PartialCombinatorApplicationDeclaration', {
        id,
        expression: makeNode('EExpression', {
          subexpressions: extractLast(subexprs)
        })
      })
    }

// ---Type finalization---

FinalDecl
  = NewKw __ ident:BoxedTypeIdent __ ";"
    { return makeFinalDecl('New', ident) }
  / FinalKw __ ident:BoxedTypeIdent __ ";"
    { return makeFinalDecl('Final', ident) }
  / EmptyKw __ ident:BoxedTypeIdent __ ";"
    { return makeFinalDecl('Empty', ident) }

// --- ---

Comment
  = "//" comment:[^\r\n]* ([\r\n] / EOF)
    // { return makeNode('Comment', { value: comment.join('') }) }

// --- ---

Ws "whitespace"
  = " "
  / "\t"
  / "\r"
  / "\n"

__ "skip whitespace and comments"
  = (Ws / Comment)*

// _ "one or more whitespace"
//   = Ws+

EOF
  = !.
