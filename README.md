![Build Status](https://github.com/lbarasti/rate_limiter/workflows/Crystal%20spec/badge.svg)

# rate_limiter

TODO: Write a description here

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     rate_limiter:
       github: lbarasti/rate_limiter
   ```

2. Run `shards install`

## Usage

```crystal
require "rate_limiter"
```

TODO: Write usage instructions here

## Why do I need a rate limiter?
* We're calling an API that throttles us when we
  call too frequently
* we are exposing an API to customers and want to
  ensure we don't get flooded with requests
* Run ETL jobs with specified rate - e.g. query
  a datastore with a rate limit
* Run a database migration in production and we don't
  want to affect the responsiveness of the service

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/lbarasti/rate_limiter/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [lbarasti](https://github.com/lbarasti) - creator and maintainer
