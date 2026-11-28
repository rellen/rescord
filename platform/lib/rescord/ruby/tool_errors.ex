# Words for the errors that a tool of Ruby can meet and that `ash_ai` does
# not know (ADR 0069). Without them the model reads "unexpected error
# occurred" for a task that is done already, and cannot tell the person
# why. The words hold no value of a record.

defimpl AshAi.ToToolError, for: AshStateMachine.Errors.NoMatchingTransition do
  def to_tool_error(_error), do: "this is not in a state that allows it any more"
end

defimpl AshAi.ToToolError, for: Ash.Error.Changes.StaleRecord do
  def to_tool_error(_error), do: "somebody changed this a moment ago: read it again"
end
