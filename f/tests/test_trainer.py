import ast, pathlib
p=pathlib.Path(__file__).parents[1]/"python"/"02_train_lightgbm.py"
ast.parse(p.read_text(encoding="utf-8"))
text=p.read_text(encoding="utf-8")
assert "Yu_SCORE2_Protein257_plus_YYScore257" in text
assert "paired matrix contract" in text
print("ALL PYTHON STATIC TESTS PASSED")
