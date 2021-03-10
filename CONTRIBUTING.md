# Contributing

Anyone should feel free to make a pull request and contribute to vaccinetime.
If you find a bug or have a feature request, please open an issue in this repo.

## Branch Organization

Submit all changes directly to the `main branch`. We don't use separate
branches for development.

## Architecture

At a high level, the bot is a collection of site scrapers that run on an
interval and check for appointments. When a site shows appointments, the bot
looks at whether the number of appointments is greater than the previously seen
amount and only then sends a tweet. It also only tweets when a certain
threshold of appointments is seen, currently set at 10. This keeps the number
of Tweets down and ensures only significant appointment drops actually get
sent, rather than tweeting every time there's a cancellation.

The Ruby code is predominantly programmed in an object oriented style, with the
main loop contained in [run.rb](run.rb) and all other modules available under
[lib/](lib/). The main loop is a simple infinite `loop do` with a `sleep`
command to pause one minute between site scraping so that we don't DOS the
sites or get rate limited.

Before the main loop, the bot runs an initialization phase where it creates
clients to interact with Redis, Slack, and Twitter. At this stage if the
`SEED_REDIS` environment variable is set it will run through all the site
scrapers once and then stores those results in Redis for future comparison. By
seeding the data once in this way we can deploy to new environments with an
empty Redis without sending erroneous tweets accidentally.

Site scrapers are split into separate modules under [lib/sites/](lib/sites/).
Each implements custom logic to fetch vaccine appointments for the given
website with either a site scraper using [Nokogiri](https://nokogiri.org/) or
using their JSON API if available. These modules should expose an `all_clinics`
method which returns a list of `Clinic` objects and that will be called in
[run.rb](run.rb). A `Clinic` represents a single location on a particular date,
and encodes information about the site, the number of appointments found, and
anything else needed to encode a message for it. `Clinic` objects receive
dependencies via dependency injection so that they are loosely coupled.
