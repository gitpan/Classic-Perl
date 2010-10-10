/* This file is part of the Classic::Perl module.
 * See http://search.cpan.org/dist/Classic-Perl/ */

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define CP_HAS_PERL(R, V, S)                        \
  (                                                  \
     PERL_REVISION > (R)                              \
  || (                                                 \
        PERL_REVISION == (R)                            \
     && (                                                \
           PERL_VERSION > (V)                             \
        || (PERL_VERSION == (V) && PERL_SUBVERSION >= (S)) \
        )                                                   \
     )                                                       \
  )
#if CP_HAS_PERL(5,13,7)
# define CP_HAS_REFLAGS
#endif

/* Features */
#if CP_HAS_PERL(5, 11, 0)
# define CP_SPLIT
#endif
#define CP_MULTILINE

STATIC SV * cp_hint(pTHX_ char *key, U32 keylen) {
#define cp_hint(a,b) cp_hint(aTHX_ (a),(b))
 SV **val
  = hv_fetch(GvHV(PL_hintgv), key, keylen, 0);
 if (!val)
  return 0;
 return *val;
}

/* ... op => info map ...................................................... */

typedef struct {
 OP *(*old_pp)(pTHX);
} cp_op_info;

#define PTABLE_NAME        ptable_map
#define PTABLE_VAL_FREE(V) PerlMemShared_free(V)

#include "ptable.h"

/* PerlMemShared_free() needs the [ap]PTBLMS_? default values */
#define ptable_map_store(T, K, V) ptable_map_store(aPTBLMS_ (T), (K), (V))

STATIC ptable *cp_op_map = NULL;

#ifdef USE_ITHREADS
STATIC perl_mutex cp_op_map_mutex;
#endif

STATIC const cp_op_info *cp_map_fetch(const OP *o, cp_op_info *oi) {
 const cp_op_info *val;

#ifdef USE_ITHREADS
 MUTEX_LOCK(&cp_op_map_mutex);
#endif

 val = ptable_fetch(cp_op_map, o);
 if (val) {
  *oi = *val;
  val = oi;
 }

#ifdef USE_ITHREADS
 MUTEX_UNLOCK(&cp_op_map_mutex);
#endif

 return val;
}

STATIC const cp_op_info *cp_map_store_locked(
 pPTBLMS_ const OP *o, OP *(*old_pp)(pTHX)
) {
#define cp_map_store_locked(O, PP) \
  cp_map_store_locked(aPTBLMS_ (O), (PP))
 cp_op_info *oi;

 if (!(oi = ptable_fetch(cp_op_map, o))) {
  oi = PerlMemShared_malloc(sizeof *oi);
  ptable_map_store(cp_op_map, o, oi);
 }

 oi->old_pp = old_pp;
/* oi->next   = next;
 oi->flags  = flags;
*/
 return oi;
}

STATIC void cp_map_store(
 pPTBLMS_ const OP *o, OP *(*old_pp)(pTHX))
{
#define cp_map_store(O, PP) cp_map_store(aPTBLMS_ (O),(PP))

#ifdef USE_ITHREADS
 MUTEX_LOCK(&cp_op_map_mutex);
#endif

 cp_map_store_locked(o, old_pp);

#ifdef USE_ITHREADS
 MUTEX_UNLOCK(&cp_op_map_mutex);
#endif
}

STATIC void cp_map_delete(pTHX_ const OP *o) {
#define cp_map_delete(O) cp_map_delete(aTHX_ (O))
#ifdef USE_ITHREADS
 MUTEX_LOCK(&cp_op_map_mutex);
#endif

 ptable_map_store(cp_op_map, o, NULL);

#ifdef USE_ITHREADS
 MUTEX_UNLOCK(&cp_op_map_mutex);
#endif
}


/* ========== SPLIT FEATURE ========== */

/* How this works

Way down at the bottom of this file,  we override the PL_check[OP_SPLIT]
function (assigning to it after saving the old value). The override calls
the original function and then,  if the pragma is in scope and the  split
does not have a gv, we replace the op’s pp function with our own wrapper
around pp_split.

To avoid the void warning, we have to give the op a gv. The only problem is
that in the  PL_check  function we don’t yet know what the context will be.
We don’t want to split to @_ in list context, so we delete the @_ temporar-
ily in our pp_ function. It has to be temporary, as split could be the last
statement of a subroutine,  in which case the context may be different each
time it is executed.

*/

#ifdef CP_SPLIT

/* --- PP functions -------------------------------------------------------- */


STATIC OP *cp_pp_split(pTHX) {
 cp_op_info oi;
 dSP;
 register PMOP *pm;
 OP *retval;
 const I32 gimme = GIMME_V;
#ifdef USE_ITHREADS
 PADOFFSET offset;
#endif

#ifdef DEBUGGING
  Copy(&LvTARGOFF(*(SP-2)), &pm, 1, PMOP*);
#else
  pm = (PMOP*)*(SP-2);
#endif

#ifdef USE_ITHREADS
 if(gimme == G_ARRAY) {
  offset = pm->op_pmreplrootu.op_pmtargetoff;
  pm->op_pmreplrootu.op_pmtargetoff = 0;
 }
#else
 if(gimme == G_ARRAY)
  pm->op_pmreplrootu.op_pmtargetgv = NULL;
#endif

 cp_map_fetch(PL_op, &oi);

 retval = (*oi.old_pp)(aTHX);

 /* Restore the PL_defgv in case it’s in scalar or void context next time.
  */
 if(gimme == G_ARRAY)
#ifdef USE_ITHREADS
  pm->op_pmreplrootu.op_pmtargetoff = offset;
#else
  pm->op_pmreplrootu.op_pmtargetgv = PL_defgv;
#endif

 return retval;  
}

/* --- Check functions ----------------------------------------------------- */

#define split     "Classic_Perl__split"
#define split_len  (sizeof(split)-1)


STATIC OP *(*cp_old_ck_split)(pTHX_ OP *) = 0;

STATIC OP *cp_ck_split(pTHX_ OP *o) {
 SV *hintsv = cp_hint(split, split_len);
 IV hint = hintsv ? SvTRUE(hintsv) : 0;

 o = (*cp_old_ck_split)(aTHX_ o);

 if (hint) {
  register PMOP *pm = (PMOP*)((LISTOP*)o)->op_first;
#ifdef USE_ITHREADS
  if (!pm->op_pmreplrootu.op_pmtargetoff) {
   /* This technique is copied from Perl_ck_rvconst, which is where split
      usually gets its ‘padded’ gv from ultimately. */
   /* When I put the assignment inside the PAD_SVl I sometimes get a SEGV
      (with make disttest, but not make test). Strange! */
   pm->op_pmreplrootu.op_pmtargetoff
     = Perl_pad_alloc(aTHX_ OP_SPLIT,SVs_PADTMP);
   SvREFCNT_dec(PAD_SVl(
    pm->op_pmreplrootu.op_pmtargetoff
   ));
   GvIN_PAD_on(PL_defgv);
   PL_curpad[pm->op_pmreplrootu.op_pmtargetoff] =
    (SV*)SvREFCNT_inc_simple_NN(PL_defgv)
   ;
#else
  if (!pm->op_pmreplrootu.op_pmtargetgv) {
   pm->op_pmreplrootu.op_pmtargetgv = (GV*)SvREFCNT_inc_NN(PL_defgv);
#endif

   cp_map_store(o, o->op_ppaddr);
   o->op_ppaddr = cp_pp_split;
  }
  else cp_map_delete(o);
 } else
  cp_map_delete(o);

 return o;
}

#endif /* CP_SPLIT */


/* ========== MULTILINE FEATURE ========== */

#ifdef CP_MULTILINE

/* --- Check functions ------------------------------------------------- */

#define multiline     "Classic_Perl__$*"
#define multiline_len  (sizeof(multiline)-1)


STATIC OP *(*cp_old_ck_sassign)(pTHX_ OP *) = 0;
STATIC OP *(*cp_old_ck_aassign)(pTHX_ OP *) = 0;
STATIC OP *(*cp_old_ck_match)(pTHX_ OP *) = 0;
STATIC OP *(*cp_old_ck_qr   )(pTHX_ OP *) = 0;
STATIC OP *(*cp_old_ck_subst)(pTHX_ OP *) = 0;

#ifdef CP_HAS_REFLAGS
# define set_multiline_to(num) \
   {                            \
    ENTER;                       \
    Perl_load_module(aTHX_        \
     num ? 0 : PERL_LOADMOD_DENY,  \
     newSVpvs("re"),                \
     NULL,                           \
     newSVpvs("/m"),                  \
     NULL                              \
    );                                  \
    LEAVE;                               \
   }
#else
# define set_multiline_to(num) sv_setiv_mg(hintsv, (num))
#endif


STATIC OP *cp_ck_sassign(pTHX_ OP *o) {
 SV *hintsv = cp_hint(multiline, multiline_len);

 o = (*cp_old_ck_sassign)(aTHX_ o);
 if (
     hintsv && SvOK(hintsv)
  && ((BINOP *)o)->op_first->op_type == OP_CONST
  && ((BINOP *)o)->op_first->op_sibling->op_type == OP_RV2SV
  && ((BINOP *)((BINOP *)o)->op_first->op_sibling)->op_first->op_type
      == OP_GV
  && strEQ(
       GvNAME(
        cGVOPx_gv(((BINOP *)((BINOP *)o)->op_first->op_sibling)->op_first)
       ),
      "*"
     )
 ) set_multiline_to(SvIV(cSVOPx_sv(((BINOP *)o)->op_first)));

 return o;
}

STATIC OP *cp_ck_aassign(pTHX_ OP *o) {
 SV *hintsv = cp_hint(multiline, multiline_len);

 o = (*cp_old_ck_aassign)(aTHX_ o);

 if (hintsv && SvOK(hintsv)) {
  OP* right = ((BINOP *)o)->op_first;
  OP* left = ((BINOP *)right->op_sibling)->op_first->op_sibling;
  right = ((BINOP *)right)->op_first->op_sibling;
  if(  !left->op_sibling && !right->op_sibling
    && right->op_type == OP_CONST
    && left->op_type == OP_RV2SV
    && ((BINOP *)left)->op_first->op_type == OP_GV
    && strEQ(GvNAME(cGVOPx_gv(((BINOP *)left)->op_first)),"*")
  ) set_multiline_to(SvIV(cSVOPx_sv(right)));
 }

 return o;
}

#ifndef CP_HAS_REFLAGS
#define ck_match_func(optype)                   \
 STATIC OP *cp_ck_##optype(pTHX_ OP *o) {        \
  SV *hintsv = cp_hint(multiline, multiline_len); \
                                                   \
  o = (*cp_old_ck_##optype)(aTHX_ o);               \
                                                     \
  if (hintsv && SvOK(hintsv) && SvIV(hintsv))         \
   ((PMOP *)o)->op_pmflags |= RXf_PMf_MULTILINE;       \
                                                        \
  return o;                                              \
 }

ck_match_func(match)
ck_match_func(qr   )
ck_match_func(subst)
#endif

#endif /* CP_MULTILINE */


STATIC U32 cp_initialized = 0;

/* --- XS ------------------------------------------------------------------ */

MODULE = Classic::Perl      PACKAGE = Classic::Perl

PROTOTYPES: ENABLE

BOOT: 
{                                    
 if (!cp_initialized++) {

  cp_op_map = ptable_new();
#ifdef USE_ITHREADS
  MUTEX_INIT(&cp_op_map_mutex);
#endif
 /**/
#ifdef CP_SPLIT
  cp_old_ck_split        = PL_check[OP_SPLIT];
  PL_check[OP_SPLIT]     = cp_ck_split;
#endif
 /**/
#ifdef CP_MULTILINE
  cp_old_ck_sassign      = PL_check[OP_SASSIGN];
  cp_old_ck_aassign      = PL_check[OP_AASSIGN];
#ifndef CP_HAS_REFLAGS
  cp_old_ck_match        = PL_check[OP_MATCH  ];
  cp_old_ck_qr           = PL_check[OP_QR     ];
  cp_old_ck_subst        = PL_check[OP_SUBST  ];
#endif
  PL_check[OP_SASSIGN]   = cp_ck_sassign;
  PL_check[OP_AASSIGN]   = cp_ck_aassign;
#ifndef CP_HAS_REFLAGS
  PL_check[OP_MATCH  ]   = cp_ck_match;
  PL_check[OP_QR     ]   = cp_ck_qr   ;
  PL_check[OP_SUBST  ]   = cp_ck_subst;
#endif
#endif
 }
}
