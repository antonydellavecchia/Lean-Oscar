import Mathlib
import Mrdi.Basic
import Mrdi.Stream
import Mrdi.ToExpr
import Mrdi.Server
import Mrdi.ToMrdiNoncomputable
import Std
import Qq
import Mathlib.Tactic.ToExpr

namespace Mrdi.Tactic

open Qq Lean Elab Tactic Meta IO.MrdiFile Expr Server

/-- `load_file file` loads from mrdi-files/file.mrdi -/
syntax "load_file " term : tactic
elab_rules : tactic
  | `(tactic| load_file $file) => do
    let fileE ← elabTerm file q(String)
    let goal ← getMainGoal
    goal.withContext do
      let α ← goal.getType
      let a ← IO.MrdiFile.loadMrdiFromFile α fileE (trace := False)
      goal.assign a


section Matrix_inverse

/-- Takes a matrix, returns the type of the elements and the dimensions -/
private def matrixType (u) (x : Q(Type $u)) : MetaM (Q(Type u) × Q(ℕ) × Q(ℕ)) := match x with
  | ~q(((Matrix (Fin ($m + 1)) (Fin ($n + 1)))) $α) => return (q($α), q($m) ,q($n))
  | _ => throwError "input didn't match expected type"

def matrix_inverse' (A : Expr) (goal : MVarId) : TacticM Unit := do
  let tA ← inferType A
  let .sort u ← instantiateMVars (← whnf (← inferType tA)) | unreachable!
  let some v := u.dec | throwError "not a type{indentExpr tA}"
  let (α, m, n) ← matrixType ql(v) tA
  let A_mrdi : Mrdi ← Mrdi? A
  let inv_mrdi ← julia "matrix inverse" A_mrdi
  let inv : Q(Matrix (Fin ($m + 1)) (Fin ($n + 1)) $α) ← evalMrdi q(Matrix (Fin ($m + 1)) (Fin ($n + 1)) $α) inv_mrdi
  goal.assign inv
  return

def matrix_inverse (A : Expr) (goal : MVarId) : TacticM Unit := do
  let tA ← inferType A
  let .sort u ← instantiateMVars (← whnf (← inferType tA)) | unreachable!
  let some v := u.dec | throwError "not a type{indentExpr tA}"
  let (α, m, n) ← matrixType ql(v) tA
  let inv ← julia' "matrix inverse" A q(Matrix (Fin ($m + 1)) (Fin ($n + 1)) $α)
  goal.assign inv
  return

syntax "matrix_inverse " term : tactic
elab_rules : tactic
  | `(tactic| matrix_inverse $A) => do
    let A ← elabTerm A none
    let goal ← getMainGoal
    matrix_inverse A goal

end Matrix_inverse


section Permutation

-- TODO this definition probably exists in Mathlib
def List.toSet : List α → Set α
 | [] => {}
 | [a] => {a}
 | a :: as => Set.insert a (List.toSet as)

lemma List.toSet_insert {a : α} {as : List α} : List.toSet (a :: as) = Set.insert a (List.toSet as) := by
  induction as
  · simp only [toSet]
    exact Set.toFinset_inj.mp rfl
  · rfl

-- TODO this could be added to Mathlib
@[simp] theorem Set.mem_insert_self {α : Type u_1} (a : α) (s : Set α) : a ∈ Set.insert a s := by
  left
  rfl

theorem List.toSet_mem {a : α} {l : List α} : a ∈ List.toSet l ↔ a ∈ l := by
  induction l with
   | nil => simp only [Set.mem_empty_iff_false, List.not_mem_nil, List.toSet]
   | cons x xs h =>
      by_cases hax : x = a
      · simp [List.toSet_insert, hax, h]
      · simp [List.toSet_insert, hax, h]
        constructor
        · intro h2
          right
          rw [← h]
          apply Set.mem_of_mem_insert_of_ne h2 (Ne.symm hax)
        · rintro (rfl | h4)
          · exact (hax rfl).elim
          · right
            rw [h]
            exact h4

/-- A product of elements of a vector is in the Group generated by the elements of the vector.
    And so is the product defined by the lifting the word. -/
theorem FreeGroup_lift_word_mem_GroupClosure [Group α] {n : ℕ} (v : Vector α n) (word : FreeGroup (Fin n)) :
  let f : FreeGroup (Fin n) →* α := (FreeGroup.lift fun (i : Fin n) => Vector.get v i)
  f word ∈ Group.closure (List.toSet v.toList) := by
    have h (x : Fin n) : (FreeGroup.lift fun i => Vector.get v i) (pure x) = v.get x := FreeGroup.lift.of
    induction word using FreeGroup.induction_on with
      | C1 => apply Group.InClosure.one
      | Cp x =>
          apply Group.InClosure.basic
          simp [List.toSet_mem, h]
      | Ci x _ =>
          simp [h]
          apply Group.InClosure.inv
          apply Group.InClosure.basic
          simp [List.toSet_mem]
      | Cm x y hx hy =>
          simp [h] at *
          apply Group.InClosure.mul hx hy

-- TODO how can I use `Lean.Meta.replaceTargetEq` and get `eqProof` as a new goal without writing a new definition for it?
/--
  Convert the given goal `Ctx |- target` into `Ctx |- targetNew` and an equality proof `eqProof : target = targetNew`.
-/
def replaceTargetEq (mvarId : MVarId) (targetNew : Expr) : MetaM (MVarId × MVarId) :=
  mvarId.withContext do
    mvarId.checkNotAssigned `replaceTarget
    let target   ← mvarId.getType
    let eq       ← mkEq target targetNew
    let mvarEq   ← mkFreshExprSyntheticOpaqueMVar eq `eqProof
    let tag      ← mvarId.getTag
    let mvarNew  ← mkFreshExprSyntheticOpaqueMVar targetNew tag
    let u        ← getLevel target
    let val  := mkAppN (Lean.mkConst `Eq.mpr [u]) #[target, targetNew, mvarEq, mvarNew]
    mvarId.assign val
    return (mvarNew.mvarId!, mvarEq.mvarId!)

def PermsToList (u) (α : Q(Type $u)) (g : Q($α)) (gens : Q(Set $α)) : MetaM $ Q(List $α) × Q(List $α) := do
  let gens : Q(List $α) ← Set.toList gens
  return (q($g :: $gens), q($gens))

/- Solves goals of type `x ∈ Group.closure {a, b, c, ...}` where `x`, `a`, `b`, `c`, ... are permutations -/
def permutation (goal : MVarId) : TacticM Unit := do
  let goal_type ← goal.getType
  let some (g_type, γ, mem_inst, g, closure_set) := app5? goal_type ``Membership.mem | throwError "not a goal of type g ∈ G"
  let .sort sort_v ← inferType γ | throwError "not a sort"
  let some v := sort_v.dec | throwError "not a type{indentExpr (.sort sort_v)}"
  have γ : Q(Type $v) := γ
  have closure_set : Q($γ) := closure_set
  let .sort sort_u ← inferType g_type | throwError "not a sort"
  let some u := sort_u.dec | throwError "not a type{indentExpr (.sort sort_u)}"
  have g_type : Q(Type $u) := g_type
  have g : Q($g_type) := g
  let some (_, inst, gens) :=  closure_set.app3? ``Group.closure | throwError "G is not a Group.closure"
  have _ : Q(Group $g_type) := inst
  let (g_and_gens, gens) ← PermsToList u g_type g gens
  let n : Q(ℕ) := q(List.length $gens)
  let gens_vector : Q(Vector $g_type $n) := q(⟨$gens, rfl⟩)
  let n' ← unsafe evalExpr ℕ q(ℕ) n
  have n : Q(ℕ) := toExpr n'
  let mrdi : Mrdi ← IO.MrdiFile.Mrdi? g_and_gens
  let word_mrdi : Mrdi ← julia "permutation" mrdi
  let word : Q(FreeGroup (Fin $n)) ← evalMrdi q(FreeGroup (Fin $n)) word_mrdi
  let word : Q(Expr) := q(toExpr $word)
  let word ← unsafe evalExpr Expr q(Expr) word
  have word : Q(FreeGroup (Fin (List.length $gens))) := word
  let _ ← synthInstanceQ q(Inhabited $g_type)
  let prod := q(FreeGroup.lift (fun (x : Fin (List.length $gens)) => Vector.get $gens_vector x) $word)
  have _ : Q(Membership $g_type $γ) := mem_inst
  let targetNew := q($prod ∈ $closure_set)
  let (new_goal, eq_goal) ← replaceTargetEq goal targetNew
  let eq_goal ← eq_goal.withContext do
    let tacticCode ← `(tactic| congr; ext x; fin_cases x; any_goals rfl)
    let (eq_goal, _) ← Elab.runTactic eq_goal tacticCode
    return eq_goal
  let new_goal ← new_goal.withContext do
    let tacticCode ← `(tactic| apply FreeGroup_lift_word_mem_GroupClosure)
    let (new_goal, _) ← Elab.runTactic new_goal tacticCode
    return new_goal
  replaceMainGoal (new_goal ++ eq_goal)

/- Solves goals of type `x ∈ Group.closure {a, b, c, ...}` where `x`, `a`, `b`, `c`, ... are permutations -/
syntax "permutation " : tactic
elab_rules : tactic
  | `(tactic| permutation) => do
    let goal ← getMainGoal
    permutation goal

end Permutation

end Mrdi.Tactic
