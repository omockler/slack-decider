require 'sinatra'
require 'redis'
require 'json'

COMMAND_PATTERN = /([^:]+):([\w]+)(.*)/
HELP_TEXT = <<-EOS
https://github.com/omockler/slack-decider
Pick yes/no: /decider
Pick from options: /decider option1, option2, option3
List of lists: /decider show
Add to list: /decider add:[list_name] option[, option]
Remove list item: /decider remove-item:[list_name] option[, option]
Show list options: /decider list:[list_name]
Pick item from list: /decider pick:[list_name]
Show randomized list options: /decider shuffle:[list_name]
EOS

configure do
  REDIS = if ENV['REDIS_URL'].nil?
            Redis.new
          else
            uri = URI.parse(ENV['REDIS_URL'])
            Redis.new(host: uri.host, port: uri.port, password: uri.password)
          end
end

helpers do
  include Rack::Utils

  def require_key!
    @token = params['token']
    halt 403 unless ENV['TOKEN'].split("|").include?(@token)
  end

  def list_set_key(list = @list, token = @token)
    "list:#{token}:#{list}"
  end

  def parse_command
    text = unescape(params['text']).strip

    @command = case
               when text.empty?
                 'yes_no'
               when ['help', 'show', 'piname'].include?(text.downcase)
                 text.downcase
               when match = COMMAND_PATTERN.match(text)
                 match.captures
               else
                 'default_pick'
               end

    @command, @list, @args = @command if @command.is_a? Array
    @args ||= text
    @args = @args.split(',').map(&:strip)
  end
end

before do
  pass if request.path_info == '/'
  require_key!
  halt 500 if params['text'].nil?
  parse_command
end

set(:command) do |option|
  condition do
    @command == option
  end
end

post '/choose', command: 'default_pick' do
  content_type :json
  {
    response_type:  'in_channel',
    text: @args.join(', '),
    attachments: [{
      text: @args.sample
    }]
  }.to_json
end

post '/choose', command: 'add' do
  REDIS.sadd(list_set_key, @args.map(&:downcase))
  "#{@args.join(', ')} added to #{@list} list"
end

post '/choose', command: 'remove-item' do
  content_type :json
  num_removed = REDIS.srem(list_set_key, @args.map(&:downcase))
  items = REDIS.smembers(list_set_key)
  {
    response_type: 'ephemeral',
    text: "Removed #{num_removed} items.",
    attachments: [{
      text: "List now contains: #{items.join(', ')}"
    }]
  }.to_json
end

post '/choose', command: 'list' do
  content_type :json
  items = REDIS.smembers(list_set_key)
  {
    response_type: 'in_channel',
    text: items.join(', ')
  }.to_json
end

post '/choose', command: 'pick' do
  content_type :json
  location = REDIS.srandmember(list_set_key)
  location = "List [#{@list}] Missing" unless location
  {
    response_type: 'in_channel',
    text: location
  }.to_json
end

post '/choose', command: 'help' do
  content_type :json
  {
    response_type: 'ephemeral',
    text: 'Command Usage',
    attachments: [{
      text: HELP_TEXT
    }]
  }.to_json
end

post '/choose', command: 'show' do
  content_type :json
  # I know, I know. Should be scan but ¯\_(ツ)_/¯
  lists = REDIS.keys("list:#{@token}:*")
  {
    response_type: 'in_channel',
    text: lists.map { |l| l.split(/: */).last }.join(', ')
  }.to_json
end

post '/choose', command: 'yes_no' do
  content_type :json
  {
    response_type: 'in_channel',
    text: ['yes', 'no'].sample
  }.to_json
end

post '/choose', command: 'piname' do
  uri = URI.parse("http://piprojects.herokuapp.com/projects/random")
  projects = 3.times.map { Net::HTTP.get_response(uri) }.map { |name| JSON.parse(name.body) }
  project = projects.sample
  names = projects.map { |p| p['name'] }
  content_type :json
  {
    response_type: 'in_channel',
    :text => names.join(', '),
    :attachments => [{
                      :text => "#{project['name']}\n#{project['color']["hex"]}",
                      :color => project['color']["hex"],
                      :title => project['animal']["wiki"],
                      :title_link => project['animal']["wiki"]
                    }]
  }.to_json
end

post '/choose', command: 'shuffle' do
  content_type :json
  items = REDIS.smembers(list_set_key)
  {
    response_type: 'in_channel',
    text: items.shuffle.join(', ')
  }.to_json
end
