/* This file is part of the Classic::Perl module.
 * See http://search.cpan.org/dist/Classic-Perl/ */

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

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* Only used in op flags */
#define CP_HINT_ROOT   64

STATIC bool cp_hint(pTHX_ char *key, U32 keylen, U32 hash) {
#define cp_hint(a,b,c) cp_hint(aTHX_ (a),(b),(c))
 SV *hint;
 SV **val
  = hv_fetch(GvHV(PL_hintgv), key, keylen, hash);
 if (!val)
  return 0;
 hint = *val;

 return SvTRUE(hint);
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

/* --- PP functions -------------------------------------------------------- */


STATIC OP *cp_pp_split(pTHX) {
 cp_op_info oi;
 dSP;
 register PMOP *pm = (PMOP*)*(SP-2);
 OP *retval;
 const I32 gimme = GIMME_V;
#ifdef USE_ITHREADS
 PADOFFSET offset;

 if(gimme == G_ARRAY) {
  offset = pm->op_pmreplrootu.op_pmtargetoff;
  pm->op_pmreplrootu.op_pmtargetoff = 0;
 }
#else
 if(gimme == G_ARRAY)
  pm->op_pmreplrootu.op_pmtargetgv = NULL;
#endif

 cp_map_fetch(PL_op, &oi);

 retval = CALL_FPTR(oi.old_pp)(aTHX);

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
STATIC U32 split_hash = 0;


STATIC OP *(*cp_old_ck_split)(pTHX_ OP *) = 0;

STATIC OP *cp_ck_split(pTHX_ OP *o) {
 OP * (*new_pp)(pTHX)        = 0;
 IV hint = cp_hint(split, split_len, split_hash);
 STRLEN *w = PL_curcop->cop_warnings;

 o = CALL_FPTR(cp_old_ck_split)(aTHX_ o);

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
   PAD_SETSV(
    pm->op_pmreplrootu.op_pmtargetoff,
    (SV*)SvREFCNT_inc_simple_NN(PL_defgv)
   );
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

  PERL_HASH(split_hash, split, split_len);

  cp_old_ck_split        = PL_check[OP_SPLIT];
  PL_check[OP_SPLIT]     = MEMBER_TO_FPTR(cp_ck_split);

 }
}
