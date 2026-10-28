(* Reads a .nb (path in $WLNBInput) and writes JSON cells to $WLNBOutput:
   [{"type": "code"|"markdown"|"output", "text": ..., "png": base64 (optional)}]. No front end needed. *)
cellsOf[x_] := Which[
  MatchQ[x, Notebook[_List, ___]], Flatten[cellsOf /@ x[[1]]],
  MatchQ[x, Cell[CellGroupData[_List, ___], ___]], Flatten[cellsOf /@ x[[1, 1]]],
  MatchQ[x, _Cell], {x},
  True, {}];

crude[s_String] := s;
crude[RowBox[l_List]] := StringJoin[crude /@ l];
crude[l_List] := StringJoin[crude /@ l];
crude[StyleBox[x_, ___]] := crude[x];
crude[SubscriptBox[a_, b_]] := crude[a] <> "_" <> crude[b];
crude[SuperscriptBox[a_, b_]] := crude[a] <> "^" <> crude[b];
crude[SubsuperscriptBox[a_, b_, c_]] := crude[a] <> "_" <> crude[b] <> "^" <> crude[c];
crude[FractionBox[a_, b_]] := "(" <> crude[a] <> ")/(" <> crude[b] <> ")";
crude[SqrtBox[a_]] := "Sqrt[" <> crude[a] <> "]";
crude[TextData[x_]] := crude[x];
crude[BoxData[x_]] := crude[x];
crude[Cell[x_, ___]] := crude[x];
crude[ButtonBox[x_, ___]] := crude[x];
crude[_] := "";

(* InputForm text of an expression held in HoldForm/HoldComplete, without evaluating it *)
unwrap[s_String] := StringReplace[s, StartOfString ~~ "HoldForm[" ~~ r__ ~~ "]" ~~ EndOfString :> r];
heldText[HoldComplete[x___]] := unwrap@ToString[HoldForm[x], InputForm, PageWidth -> 90];

(* code text of a cell body: a string stays as is; boxes are parsed to an expression and printed as InputForm *)
codeText[s_String] := s;
codeText[BoxData[b_]] := Quiet@Check[
  With[{e = ToExpression[b, StandardForm, HoldComplete]}, If[MatchQ[e, _HoldComplete], heldText[e], crude[b]]], crude[b]];
codeText[x_] := crude[x];

(* inline formulas inside text *)
textOf[s_String] := s;
textOf[TextData[x_]] := textOf[x];
textOf[l_List] := StringJoin[textOf /@ l];
textOf[Cell[BoxData[b_], ___]] := "`" <> codeText[BoxData[b]] <> "`";
textOf[StyleBox[x_, ___]] := textOf[x];
textOf[ButtonBox[x_, ___]] := textOf[x];
textOf[BoxData[b_]] := crude[b];
textOf[x_] := crude[x];

heading = <|"Title" -> "# ", "Subtitle" -> "## ", "Chapter" -> "# ", "Section" -> "## ", "Subsection" -> "### ",
  "Subsubsection" -> "#### ", "Subsubsubsection" -> "##### "|>;
textStyles = {"Text", "MathCaption", "SmallText", "Caption", "Item", "ItemNumbered", "Subitem", "ItemParagraph"};

outputItem[c_Cell] := Module[{b = c[[1]], e, text, png = None},
  e = Quiet@Check[If[MatchQ[b, BoxData[_]], ToExpression[b[[1]], StandardForm, HoldComplete], $Failed], $Failed];
  Which[
    MatchQ[e, HoldComplete[_Graphics | _Graphics3D | _Image]],
      text = "-Graphics-";
      png = Quiet@Check[BaseEncode[ExportByteArray[ReleaseHold[e /. HoldComplete[x_] :> x], "PNG"]], None],
    MatchQ[e, HoldComplete[_]], text = heldText[e],
    True, text = StringTrim[textOf[b]]];
  <|"type" -> "output", "text" -> text, "png" -> png|>];

convert[c : Cell[body_, style_String, ___]] := Which[
  MemberQ[{"Input", "Code"}, style], {<|"type" -> "code", "text" -> StringTrim[codeText[body]]|>},
  style === "Output", {outputItem[c]},
  MemberQ[{"Print", "Message", "Echo"}, style], {<|"type" -> "output", "text" -> StringTrim[textOf[body]], "png" -> None|>},
  KeyExistsQ[heading, style], {<|"type" -> "markdown", "text" -> heading[style] <> StringTrim[textOf[body]]|>},
  MemberQ[textStyles, style], {<|"type" -> "markdown", "text" -> StringTrim[textOf[body]]|>},
  True, {}];
convert[_] := {};

nb = Import[$WLNBInput, "NB"];
items = Flatten[convert /@ cellsOf[nb]];
items = Select[items, StringLength[#["text"]] > 0 || #["png"] =!= None &];
items = items /. None -> Null;
Export[$WLNBOutput, items, "RawJSON", "Compact" -> True];
Exit[]
