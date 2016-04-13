require "sinatra"
require "redis"
require "json"

COMMAND_PATTERN = /([^:]+):([\w]+)(.*)/

configure do
  REDIS = if ENV["REDIS_URL"].nil?
            Redis.new
          else
            uri = URI.parse(ENV["REDIS_URL"])
            Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
          end
end

helpers do
  include Rack::Utils

  def require_key!
    halt 403 unless ENV["TOKEN"] == params["token"]
  end

  def list_set_key(list = @list)
    "list:#{list}"
  end

  def parse_command
    text = unescape(params["text"]).strip
    match = COMMAND_PATTERN.match(text)
    if match
      @command, @list, @args = match.captures
    else
      @command = ["help", "show"].include?(text.downcase) ? text.downcase : "default_pick"
      @args = text
    end
    @args = @args.split(',').map(&:strip)
  end
end

before do
  pass if request.path_info == "/"
  require_key!
  halt 500 if params["text"].nil?
  parse_command
end

set(:command) do |option|
  condition do
    @command == option
  end
end

get '/?' do
  REDIS.set "test", "HI"
  REDIS.get "test"
end

post "/choose", command: "default_pick" do
  content_type :json
  {
    response_type:  "in_channel",
    text: @args.join(", "),
    attachments: [{ "text": @args.sample }]
  }.to_json
end

post "/choose", command: "add" do
  REDIS.sadd(list_set_key, @args.map(&:downcase))
  "#{@args.join(", ")} added to #{@list} list"
end

post "/choose", command: "list" do
  content_type :json
  items = REDIS.smembers(list_set_key)
  {
    response_type: "in_channel",
    text: items.join(", ")
  }.to_json
end

post "/choose", command: "pick" do
  content_type :json
  location = REDIS.srandmember(list_set_key)
  {
    response_type: "in_channel",
    text: location
  }.to_json
end

post "/choose", command: "help" do
  content_type :json
  {
    response_type: "ephemeral",
    text: "Command Usage",
    attachments: [{
      text: "/decider option1, option2, option3\n /decider add:[list_name] option[, option]\n /decider list:[list_name]\n /decider pick:[list_name]"
    }]
  }.to_json
end

post "/choose", command: "show" do
  content_type :json
  lists = REDIS.keys("list:*") # I know, I know. Should be scan but ¯\_(ツ)_/¯
  {
    response_type: "in_channel",
    text: lists.join(", ")
  }.to_json
end

