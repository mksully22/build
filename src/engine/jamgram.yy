/*
 * Copyright 1993, 2000 Christopher Seiwald.
 *
 * This file is part of Jam - see jam.c for Copyright information.
 */

/*
 * jamgram.yy - jam grammar
 *
 * 04/13/94 (seiwald) - added shorthand L0 for null list pointer
 * 06/01/94 (seiwald) - new 'actions existing' does existing sources
 * 08/23/94 (seiwald) - Support for '+=' (append to variable)
 * 08/31/94 (seiwald) - Allow ?= as alias for "default =".
 * 09/15/94 (seiwald) - if conditionals take only single arguments, so
 *			that 'if foo == bar' gives syntax error (use =).
 * 02/11/95 (seiwald) - when scanning arguments to rules, only treat
 *			punctuation keywords as keywords.  All arg lists
 *			are terminated with punctuation keywords.
 *
 * 09/11/00 (seiwald) - Support for function calls:
 *
 *		Rules now return lists (LIST *), rather than void.
 *
 *		New "[ rule ]" syntax evals rule into a LIST.
 *
 *		Lists are now generated by compile_list() and 
 *		compile_append(), and any other rule that indirectly
 *		makes a list, rather than being built directly here,
 *		so that lists values can contain rule evaluations.
 *
 *		New 'return' rule sets the return value, though
 *		other statements also may have return values.
 *
 *		'run' production split from 'block' production so 
 *		that empty blocks can be handled separately.
 */

%token ARG STRING

%left `||`
%left `&&`
%left `!`

%{
#include "jam.h"

#include "lists.h"
#include "parse.h"
#include "scan.h"
#include "compile.h"
#include "newstr.h"

# define F0 (LIST *(*)(PARSE *, FRAME *))0
# define P0 (PARSE *)0
# define S0 (char *)0

# define pappend( l,r )    	parse_make( compile_append,l,r,P0,S0,S0,0 )
# define pfor( s,l,r,x )    	parse_make( compile_foreach,l,r,P0,s,S0,x )
# define pif( l,r,t )	  	parse_make( compile_if,l,r,t,S0,S0,0 )
# define pwhile( l,r )	  	parse_make( compile_while,l,r,P0,S0,S0,0 )
# define pincl( l )       	parse_make( compile_include,l,P0,P0,S0,S0,0 )
# define plist( s )	  	parse_make( compile_list,P0,P0,P0,s,S0,0 )
# define plocal( l,r,t )  	parse_make( compile_local,l,r,t,S0,S0,0 )
# define pmodule( l,r )	  	parse_make( compile_module,l,r,P0,S0,S0,0 )
# define pnull()	  	parse_make( compile_null,P0,P0,P0,S0,S0,0 )
# define prule( s,p )     	parse_make( compile_rule,p,P0,P0,s,S0,0 )
# define prules( l,r )	  	parse_make( compile_rules,l,r,P0,S0,S0,0 )
# define pset( l,r,a )          parse_make( compile_set,l,r,P0,S0,S0,a )
# define psetmodule( l,r ) 	parse_make( compile_set_module,l,r,P0,S0,S0,0 )
# define pset1( l,r,t,a )	parse_make( compile_settings,l,r,t,S0,S0,a )
# define psetc( s,p )     	parse_make( compile_setcomp,p,P0,P0,s,S0,0 )
# define psetc_args( s,p,a )    parse_make( compile_setcomp,p,a,P0,s,S0,0 )
# define psete( s,l,s1,f ) 	parse_make( compile_setexec,l,P0,P0,s,s1,f )
# define pswitch( l,r )   	parse_make( compile_switch,l,r,P0,S0,S0,0 )

# define pnode( l,r )    	parse_make( F0,l,r,P0,S0,S0,0 )
# define pcnode( c,l,r )	parse_make( F0,l,r,P0,S0,S0,c )
# define psnode( s,l )     	parse_make( F0,l,P0,P0,s,S0,0 )

%}

%%

run	: /* empty */
		/* do nothing */
	| rules
		{ parse_save( $1.parse ); }
	;

/*
 * block - zero or more rules
 * rules - one or more rules
 * rule - any one of jam's rules
 * right-recursive so rules execute in order.
 */

block	: /* empty */
		{ $$.parse = pnull(); }
	| rules
		{ $$.parse = $1.parse; }
	;

rules	: rule
		{ $$.parse = $1.parse; }
	| rule rules
		{ $$.parse = prules( $1.parse, $2.parse ); }
	| `local` list assign_list_opt `;` block
		{ $$.parse = plocal( $2.parse, $3.parse, $5.parse ); }
	;

assign_list_opt : /* empty */
                { $$.parse = pnull(); }
        | `=` list
                { $$.parse = $2.parse; }
        ;

rule	: `{` block `}`
		{ $$.parse = $2.parse; }
	| `include` list `;`
		{ $$.parse = pincl( $2.parse ); }
	| ARG lol `;`
		{ $$.parse = prule( $1.string, $2.parse ); }
	| arg assign list `;`
		{ $$.parse = pset( $1.parse, $3.parse, $2.number ); }
	| `module` `local` list assign_list_opt `;`
		{ $$.parse = psetmodule( $3.parse, $4.parse ); }
	| arg `on` list assign list `;`
		{ $$.parse = pset1( $1.parse, $3.parse, $5.parse, $4.number ); }
	| `return` list `;`
		{ $$.parse = $2.parse; }
	| `for` ARG `in` list `{` block `}`
		{ $$.parse = pfor( $2.string, $4.parse, $6.parse, 0 ); }
	| `for` `local` ARG `in` list `{` block `}`
		{ $$.parse = pfor( $3.string, $5.parse, $7.parse, 1 ); }
	| `switch` list `{` cases `}`
		{ $$.parse = pswitch( $2.parse, $4.parse ); }
	| `if` cond `{` block `}` 
		{ $$.parse = pif( $2.parse, $4.parse, pnull() ); }
	| `module` list `{` block `}` 
		{ $$.parse = pmodule( $2.parse, $4.parse ); }
	| `while` cond `{` block `}` 
		{ $$.parse = pwhile( $2.parse, $4.parse ); }
	| `if` cond `{` block `}` `else` rule
		{ $$.parse = pif( $2.parse, $4.parse, $7.parse ); }
        | `rule` ARG `(` lol `)` rule
		{ $$.parse = psetc_args( $2.string, $6.parse, $4.parse ); }
	| `rule` ARG rule
		{ $$.parse = psetc( $2.string, $3.parse ); }
	| `actions` eflags ARG bindlist `{`
		{ yymode( SCAN_STRING ); }
	  STRING 
		{ yymode( SCAN_NORMAL ); }
	  `}`
		{ $$.parse = psete( $3.string,$4.parse,$7.string,$2.number ); }
	;

/*
 * assign - = or +=
 */

assign	: `=`
		{ $$.number = ASSIGN_SET; }
	| `+=`
		{ $$.number = ASSIGN_APPEND; }
	| `?=`
		{ $$.number = ASSIGN_DEFAULT; }
	| `default` `=`
		{ $$.number = ASSIGN_DEFAULT; }
	;

/*
 * cond - a conditional for 'if'
 */

cond	: arg 
		{ $$.parse = pcnode( COND_EXISTS, $1.parse, pnull() ); }
	| arg `=` arg 
		{ $$.parse = pcnode( COND_EQUALS, $1.parse, $3.parse ); }
	| arg `!=` arg
		{ $$.parse = pcnode( COND_NOTEQ, $1.parse, $3.parse ); }
	| arg `<` arg
		{ $$.parse = pcnode( COND_LESS, $1.parse, $3.parse ); }
	| arg `<=` arg 
		{ $$.parse = pcnode( COND_LESSEQ, $1.parse, $3.parse ); }
	| arg `>` arg 
		{ $$.parse = pcnode( COND_MORE, $1.parse, $3.parse ); }
	| arg `>=` arg 
		{ $$.parse = pcnode( COND_MOREEQ, $1.parse, $3.parse ); }
	| arg `in` list
		{ $$.parse = pcnode( COND_IN, $1.parse, $3.parse ); }
	| `!` cond
		{ $$.parse = pcnode( COND_NOT, $2.parse, P0 ); }
	| cond `&&` cond 
		{ $$.parse = pcnode( COND_AND, $1.parse, $3.parse ); }
	| cond `||` cond
		{ $$.parse = pcnode( COND_OR, $1.parse, $3.parse ); }
	| `(` cond `)`
		{ $$.parse = $2.parse; }
	;

/*
 * cases - action elements inside a 'switch'
 * case - a single action element inside a 'switch'
 * right-recursive rule so cases can be examined in order.
 */

cases	: /* empty */
		{ $$.parse = P0; }
	| case cases
		{ $$.parse = pnode( $1.parse, $2.parse ); }
	;

case	: `case` ARG `:` block
		{ $$.parse = psnode( $2.string, $4.parse ); }
	;

/*
 * lol - list of lists
 * right-recursive rule so that lists can be added in order.
 */

lol	: list
		{ $$.parse = pnode( P0, $1.parse ); }
	| list `:` lol
		{ $$.parse = pnode( $3.parse, $1.parse ); }
	;

/*
 * list - zero or more args in a LIST
 * listp - list (in puncutation only mode)
 * arg - one ARG or function call
 */

list	: listp
		{ $$.parse = $1.parse; yymode( SCAN_NORMAL ); }
	;

listp	: /* empty */
		{ $$.parse = pnull(); yymode( SCAN_PUNCT ); }
	| listp arg
	{ $$.parse = pappend( $1.parse, $2.parse ); }
	;

arg	: ARG 
		{ $$.parse = plist( $1.string ); }
	| `[` ARG lol `]`
		{ $$.parse = prule( $2.string, $3.parse ); }
	;


/*
 * eflags - zero or more modifiers to 'executes'
 * eflag - a single modifier to 'executes'
 */

eflags	: /* empty */
		{ $$.number = 0; }
	| eflags eflag
		{ $$.number = $1.number | $2.number; }
	;

eflag	: `updated`
		{ $$.number = EXEC_UPDATED; }
	| `together`
		{ $$.number = EXEC_TOGETHER; }
	| `ignore`
		{ $$.number = EXEC_IGNORE; }
	| `quietly`
		{ $$.number = EXEC_QUIETLY; }
	| `piecemeal`
		{ $$.number = EXEC_PIECEMEAL; }
	| `existing`
		{ $$.number = EXEC_EXISTING; }
	;


/*
 * bindlist - list of variable to bind for an action
 */

bindlist : /* empty */
		{ $$.parse = pnull(); }
	| `bind` list
		{ $$.parse = $2.parse; }
	;


