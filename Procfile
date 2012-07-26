web:              bundle exec rails server thin -p $PORT -e $RACK_ENV
scheduler:        bundle exec rake resque:scheduler
worker:           bundle exec rake resque:work QUEUE=fast,neo4j,medium,mailer,slow,popularity,feeds,images,notifications
tweet_stream:     bundle exec rake environment tweet_stream:userstream