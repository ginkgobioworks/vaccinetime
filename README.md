# vaccinetime

https://twitter.com/vaccinetime/

This bot checks Massachusetts vaccine appointment sites every minute and posts
on Twitter when new appointments show up. The bot is written in
[Ruby](https://www.ruby-lang.org/en/).

## Integrated appointment websites

The following websites are currently checked:

* https://www.maimmunizations.org - every site
* https://curative.com - DoubleTree Hotel in Danvers, Eastfield Mall in Springfield, and Circuit City in Dartmouth
* https://home.color.com - Natick Mall, Reggie Lewis Center, Gillette Stadium, Fenway Park, Hynes Convention Center
* https://www.cvs.com - CVS pharmacies in MA
* https://www.lowellgeneralvaccine.com - Lowell General Hospital
* MyChart - UMass Memorial, SBCHC, BMC
* https://www.tuftsmcvaccine.org - Tufts Medical Center Vaccine Site
* https://www.harringtonhospital.org - Southbridge Community Center

## Quick start

A Dockerfile is provided for easy portability. Use docker-compose to run:

```bash
docker-compose up
```

This will run the bot without tweeting, instead sending any activity to a
"FakeTwitter" class that outputs to the terminal. Logs are also stored in files
in the `log/` directory. To set up real tweets, see the configuration section
below.

### Running locally

The bot uses [Redis](https://redis.io/) for storage, but has no other
dependencies. If you wish to run the bot locally, install Redis and run it
locally with `redis-server`, then run:

```bash
bundle install
bundle exec ruby run.rb
```

You can optionally run a subset of scrapers by providing an option `-s` or
`--scrapers` to the `run.rb` script like this:

```bash
bundle exec ruby run.rb -s ma_immunizations,cvs
```

Running locally works fine on MacOS, but hasn't been tested elsewhere.

## Configuration

Configuration is done via environment variables that are passed into docker at
runtime. To enable tweeting, provide the following:

* TWITTER_ACCESS_TOKEN
* TWITTER_ACCESS_TOKEN_SECRET
* TWITTER_CONSUMER_KEY
* TWITTER_CONSUMER_SECRET

This bot can also be configured to send slack notifications to a channel by
setting the following environment variables:

* SLACK_API_TOKEN
* SLACK_CHANNEL
* SLACK_USERNAME
* SLACK_ICON

Additional configuration can be done with the following:

* SENTRY_DSN - sets up error handling with [Sentry](https://sentry.io)
* ENVIRONMENT - configures Sentry environment
* UPDATE_FREQUENCY - number of seconds to wait between updates (default 60)
* SEED_REDIS - set to true to seed redis with the first batch of found
  appointments (useful for deploying to fresh redis instances)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to contribute. We
expect external contributors to adhere to the
[code of conduct](CODE_OF_CONDUCT.md).

## License

Copyright 2021 Ginkgo Bioworks

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
