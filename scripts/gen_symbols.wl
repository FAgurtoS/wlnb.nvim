(* Writes data/wolfram_symbols.json: every System` symbol with a one-line usage, for completion.
   Run: WolframKernel -noprompt -run 'Get["scripts/gen_symbols.wl"]; Exit[]' (from the repository root) *)
flat[s_String] := s;
flat[RowBox[l_List]] := StringJoin[flat /@ l];
flat[l_List] := StringJoin[flat /@ l];
flat[StyleBox[x_, ___]] := flat[x];
flat[SubscriptBox[a_, b_]] := flat[a] <> "_" <> flat[b];
flat[SuperscriptBox[a_, b_]] := flat[a] <> "^" <> flat[b];
flat[SubsuperscriptBox[a_, b_, c_]] := flat[a] <> "_" <> flat[b] <> "^" <> flat[c];
flat[FractionBox[a_, b_]] := "(" <> flat[a] <> ")/(" <> flat[b] <> ")";
flat[SqrtBox[a_]] := "Sqrt[" <> flat[a] <> "]";
flat[_] := "";
clean[u_String] := StringTrim@StringReplace[
   StringReplace[u, "\!\(\*" ~~ Shortest[b__] ~~ "\)" :> Quiet[Check[flat[ToExpression[b, InputForm]], ""]]],
   {Whitespace -> " "}];
firstSentences[s_String] := StringTake[s, UpTo[260]];
usage[n_String] := Quiet[Check[With[{u = ToExpression[n <> "::usage"]}, If[StringQ[u], firstSentences@clean[u], ""]], ""]];
names = Select[Names["System`*"], StringMatchQ[#, RegularExpression["[A-Za-z$][A-Za-z0-9$]*"]] &];
data = Association[# -> usage[#] & /@ names];
Export[FileNameJoin[{DirectoryName[$InputFileName, 2], "data", "wolfram_symbols.json"}], data, "RawJSON", "Compact" -> True];
