# vaccinetime

https://twitter.com/vaccinetime/

This bot checks Massachusetts vaccine appointment sites every minute and posts
on Twitter when new appointments show up. The bot is written in
[Ruby](https://www.ruby-lang.org/en/).

## Integrated appointment websites

The following websites are currently checked:

* [maimmunizations](https://www.maimmunizations.org) - every site
* [CVS pharmacies in MA](https://www.cvs.com)
* [Lowell General Hospital](https://www.lowellgeneralvaccine.com)
* [BMC](https://www.bmc.org/covid-19-vaccine-locations)
* [UMass Memorial](https://mychartonline.umassmemorial.org/mychart/openscheduling?specialty=15&hidespecialtysection=1)
* [SBCHC](https://forms.office.com/Pages/ResponsePage.aspx?id=J8HP3h4Z8U-yP8ih3jOCukT-1W6NpnVIp4kp5MOEapVUOTNIUVZLODVSMlNSSVc2RlVMQ1o1RjNFUy4u)
* [Lawrence General Hospital](https://lawrencegeneralcovidvaccine.as.me/schedule.php)
* [Martha's Vineyard Hospital & Nantucket VFW](https://covidvaccine.massgeneralbrigham.org/)
* [Tufts Medical Center Vaccine Site](https://www.tuftsmcvaccine.org)
* [Zocdoc](https://www.zocdoc.com/vaccine/screener?state=MA)
* [Southbridge Community Center](https://www.harringtonhospital.org)
* [Trinity Health of New England](https://www.trinityhealthofne.org)
* [Southcoast Health](https://www.southcoast.org)
* [Northampton](https://www.northamptonma.gov/2219/Vaccine-Clinics)
* [Rutland](https://www.rrecc.us/vaccine)
* [Heywood Healthcare](https://gardnervaccinations.as.me/schedule.php)
* [Vaccinespotter](https://www.vaccinespotter.org/MA/) - Pharmacies other than CVS
* [Pediatric Associates of Greater Salem](https://consumer.scheduling.athena.io/?departmentId=2804-102)
* [Costco](https://www.costco.com/covid-vaccine.html)
* [Hannaford](https://hannafordsched.rxtouch.com/rbssched/program/covid19/Patient)
* [Color](https://home.color.com) - Lawrence General Hospital

## Previously scraped websites

The following websites have moved onto the
[Massachusetts preregistration system](https://www.mass.gov/info-details/preregister-for-a-covid-19-vaccine-appointment),
so their scrapers have been disabled:

* https://curative.com - DoubleTree Hotel in Danvers, Eastfield Mall in Springfield, and Circuit City in Dartmouth
* https://home.color.com - Natick Mall, Reggie Lewis Center, Gillette Stadium, Fenway Park, Hynes Convention Center

## Quick start

A Dockerfile is provided for easy portability. Use docker-compose to run:

```bash
docker-compose up
```

This will run the bot without tweeting, instead sending any activity to a
"FakeTwitter" class that outputs to the terminal. To set up real tweets, see
the configuration section below.

Logs are stored in files in the `log/` directory, and any errors will terminate
the program by default and print the error trace. Set the environment variable
`ENVIRONMENT=production` to keep running even if an error occurs (errors will
still get logged).

### Running locally

The bot uses [Redis](https://redis.io/) for storage and Chrome or Chromium for
browser automation. If you wish to run the bot locally, install Chrome/Chromium
and Redis, and run redis locally with `redis-server`. Finally install the ruby
dependencies with:

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
* ENVIRONMENT - configures Sentry environment and error handling
* UPDATE_FREQUENCY - number of seconds to wait between updates (default 60)
* SEED_REDIS - set to true to seed redis with the first batch of found
  appointments (useful for deploying to fresh redis instances)

### Site specific configuration

There are also some site specific configurations to allow for tweaking behavior
at runtime without having to change the code:

MaImmunizations configuration:

* MA_IMMUNIZATIONS_TWEET_THRESHOLD
* MA_IMMUNIZATIONS_TWEET_INCREASE_NEEDED
* MA_IMMUNIZATIONS_TWEET_COOLDOWN

CVS and Vaccinespotter configuration:

* PHARMACY_TWEET_THRESHOLD
* PHARMACY_TWEET_INCREASE_NEEDED
* PHARMACY_TWEET_COOLDOWN

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
