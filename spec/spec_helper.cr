require "spec"
require "../src/rate_limiter"

Spec.override_default_formatter(Spec::VerboseFormatter.new)

def time(&block : -> T) : {T, Float64} forall T
  start_time = Time.utc
  res = block.call
  elapsed = (Time.utc - start_time).total_seconds
  {res, elapsed}
end