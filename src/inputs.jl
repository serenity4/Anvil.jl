@enum InteractionType begin
  DRAG
  DROP
  HOVER
  DOUBLE_CLICK
end

"A drag operation was detected, which may or may not have started in the area."
DRAG
"A drop operation was detected inside the area."
DROP
"A hover operation was detected."
HOVER
"A double click occured, with both clicks happening inside the area."
DOUBLE_CLICK
