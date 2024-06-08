import Oscar
import Mathlib
import Std


open Mrdi Lean Lean.Elab Command Term Lean.Elab.Tactic

-- Technically not necessary. The server will start the first time it is used.
#start_server

-- For debugging. Will send the data to Oscar and back
#echo (5 : ℕ)
#echo (6 : Int)

-- Defining by using a mrdi file. The file can be found at "mrdi-files/int.mrdi"
def test_int : Int := by load_file "int"
-- We can evaluate `test_int` to see the value
#eval test_int
-- or print the definition
#print test_int

-- Reading a mrdi file as command
#readMrdi Int from "int"

-- Same for words of a free group
def word : FreeGroup (Fin 4) := by load_file "free_group_word"
#readMrdi FreeGroup (Fin 4) from "free_group_word"
#print word

-- Save the word in a mrdi file
#writeMrdi word to "free_group_word2"
def word' : FreeGroup (Fin 2) := by load_file "free_group_word2"

-- The objects are equal
example : word = word' := by rfl

-- First interesting application. We are using Oscar to invert A.
def A : Matrix (Fin 3) (Fin 3) ℚ := !![3, 0, 4; 5, 10, 6; 1, 2, 3]
def A_inv : Matrix (Fin 3) (Fin 3) ℚ := by matrix_inverse A

example : A * A_inv = 1 := by
  simp [A, A_inv]
  ext i j
  fin_cases i
  all_goals fin_cases j
  any_goals norm_num [_root_.mkRat, Rat.normalize]
  any_goals rfl


namespace perm_group_membership

-- Here we automate proving that a permutation is in the group generated by some permutations.
-- It only works with permutations of `Fin n` for an arbitrary `n`. `c[1, 2]` is the cycle (1,2)

def g  : Equiv.Perm (Fin 5) := c[1, 2, 3, 4]
def g₀ : Equiv.Perm (Fin 5) := c[2, 1, 3]
def g₁ : Equiv.Perm (Fin 5) := c[1, 3, 4]
def g₂ : Equiv.Perm (Fin 5) := c[3, 2, 4]
def g₃ : Equiv.Perm (Fin 5) := c[3, 1, 4]
def g₄ : Equiv.Perm (Fin 5) := c[1, 2]

example : g ∈ Group.closure {g₀, g₁, g₂, g₃, g₄} := by
  perm_group_membership

end perm_group_membership


namespace perm_group_membership2

-- The same with different numbers.

def g  : Equiv.Perm (Fin 4) := c[1, 2, 3]
def g₀ : Equiv.Perm (Fin 4) := c[1, 3]
def g₁ : Equiv.Perm (Fin 4) := c[1, 2, 0]
def g₂ : Equiv.Perm (Fin 4) := c[1, 2]
def g₃ : Equiv.Perm (Fin 4) := c[2, 3, 1]

example : g ∈ Group.closure {g₀, g₁, g₂, g₃} := by
  perm_group_membership

end perm_group_membership2


namespace kbmag

-- Here we proof equations in finitely presented groups.
-- The proof might need some time (~45s/proof on my computer).

@[reducible]
def f := FreeGroup (Fin 2)

@[reducible]
def a : f := FreeGroup.mk [(0, true)]
@[reducible]
def b : f := FreeGroup.mk [(1, true)]

@[reducible]
def rels_list := [a⁻¹ * b⁻¹ * a * b * a⁻¹, b⁻¹ * a⁻¹ * b * a * b⁻¹]
@[reducible]
def rels := List.toSet rels_list

@[reducible]
def g := PresentedGroup rels

set_option maxRecDepth 10000000000000000000000
set_option maxHeartbeats 1000000000000000000000

theorem g_triv : ∀ (x : g), x = 1 := by
  kbmag (1 : g)

theorem g_triv' : Group.isTrivial g := by
  kbmag (1 : g)

theorem a_eq_b : (PresentedGroup.of 0 : g) = (PresentedGroup.of 1 : g) := by
  kbmag (1 : g)

end kbmag
