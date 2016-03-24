require 'sinatra'

post '/choose' do
  halt 403 unless ENV["TOKEN"] == params["token"]
  items = params["text"]
  items = items.split(",")
  items.sample
end
