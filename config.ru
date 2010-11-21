require 'kunigo'

set :run, false
# set :port, 443
set :environment, :production
set :raise_errors, true 

FileUtils.mkdir_p 'log' unless ::File.exist?('log')
log = ::File.new("log/sinatra.log", "a")
$stdout.reopen(log)
$stderr.reopen(log)

run Sinatra::Application
