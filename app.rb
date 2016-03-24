require 'sinatra'
require 'json'

post '/choose' do
  halt 403 unless ENV["TOKEN"] == params["token"]
  content_type :json
  items = params["text"]
  items = items.split(",")
  {
    response_type:  "in_channel",
    text: items.sample,
    attachments: [{ "text": params["text"] }]
  }.to_json
end
