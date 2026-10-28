(* Reads cells as JSON from $WLNBInput ([{"type": "code"|"markdown"|"raw", "text": ..., "outputs": [{"text", "png"}]}])
   and writes a Mathematica notebook to $WLNBOutput. No front end needed. *)
data = Import[$WLNBInput, "RawJSON"];

headingStyles = {"Title", "Section", "Subsection", "Subsubsection", "Subsubsubsection"};

markdownCell[text_String] := Module[{m = StringCases[text, StartOfString ~~ h : ("#" ..) ~~ " " ~~ rest__ :> {StringLength[h], rest}]},
  If[m =!= {},
    Cell[StringTrim[m[[1, 2]]], headingStyles[[Min[m[[1, 1]], Length[headingStyles]]]]],
    Cell[text, "Text"]]];

outputCell[o_Association] := Module[{text = o["text"], png = o["png"], e},
  Which[
    MemberQ[{"-Graphics-", "-Image-"}, text] && StringQ[png] && png =!= "",
      Cell[BoxData[ToBoxes[ImportByteArray[BaseDecode[png], "PNG"]]], "Output"],
    True,
      e = Quiet@Check[ToExpression[text, InputForm, HoldComplete], $Failed];
      If[MatchQ[e, HoldComplete[_]],
        Cell[BoxData[ToBoxes[e /. HoldComplete[x_] :> HoldForm[x]]], "Output"],
        Cell[text, "Output"]]]];

cellsFor[c_Association] := Switch[c["type"],
  "markdown", {markdownCell[c["text"]]},
  "raw", {Cell[c["text"], "Text"]},
  _, Join[{Cell[c["text"], "Input"]}, outputCell /@ Lookup[c, "outputs", {}]]];

Export[$WLNBOutput, Notebook[Flatten[cellsFor /@ data]], "NB"];
Exit[]
