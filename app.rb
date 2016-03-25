require "sinatra"
require "redis"
require "json"

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

  def team_lunch_key(team_id)
    "team:#{team_id}:lunch"
  end
end

get '/' do
  REDIS.set "test", "HI"
  REDIS.get "test"
end

post '/choose' do
  require_key!
  content_type :json
  items = params["text"]
  items = items.split(",")
  {
    response_type:  "in_channel",
    text: params["text"],
    attachments: [{ "text": items.sample }]
  }.to_json
end

post "/add-lunch" do
  require_key!
  halt 500 unless params["text"] && params["test"] != ""
  REDIS.sadd team_lunch_key(params["team_id"]), params["text"].downcase
  "#{params["text"]} added to lunch list"
end

post "/get-lunch" do
  require_key!
  content_type :json
  locations = REDIS.smembers team_lunch_key(params["team_id"])
  {
    response_type: "in_channel",
    text: locations.join(" ,")
  }.to_json
end

post "/pick-lunch" do
  require_key!
  content_type :json
  location = REDIS.srandmember team_lunch_key(params["team_id"])
  {
    response_type: "in_channel",
    text: "You should go to #{location}"
  }.to_json
end
