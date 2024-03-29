# coding: utf-8

require 'bundler'
Bundler.require
require 'sinatra'
require 'dotenv'
Dotenv.load
require './model_tweet'
require './track'
require './robot'
require 'pry'
require 'open-uri'
set :server, 'webrick'
set :database, "sqlite3:foo.sqlite3"
enable :sessions

  def internet_connection?
    begin
      true if open("http://www.google.com/")
    rescue
      false
    end
  end

helpers do
  alias :internet_connection? :internet_connection?
end

if internet_connection?
  uri_tweets = URI.parse(ENV["REDISTOGO_URL_TWEETS"])
  REDIS_TWEETS = Redis.new(:host => uri_tweets.host, :port => uri_tweets.port, :password => uri_tweets.password)
  uri_votes = URI.parse(ENV["REDISTOGO_URL_VOTES"])
  REDIS_VOTES = Redis.new(:host => uri_votes.host, :port => uri_votes.port, :password => uri_votes.password)
  def tweets
    REDIS_TWEETS.keys("robonova:tweet:*").map { |x| JSON.parse REDIS_TWEETS.get x }
  end
end

def remettre_a_zero(redis)
  redis = REDIS_VOTES
  redis.hset "votes", "counter1", 0
  redis.hset "votes", "counter2", 0
  redis.hset "votes", "counter3", 0
end

get '/' do
  if internet_connection?
    @redis = REDIS_TWEETS
    @redis_votes = REDIS_VOTES
    @tracks = Track.order("position")
    @tweets = tweets
    erb :twitter
  else
    @tracks = Track.order("position")
    erb :playlist
  end
end

get '/fresh_tweets' do
  @redis = REDIS_TWEETS
  @tweets = tweets
  erb :tweets, layout: false
end

post '/' do
  input = params[:input] || params[:tweet].to_s
  if input
    Track.create_track(input)
  end
  redirect to ('/')
end

post '/upload' do
  if params[:file][:type].include?('audio')
    File.open("public/tracks/#{params[:file][:filename]}", "wb") do |f|
      f.write(params[:file][:tempfile].read)
    end
    Track.create_audio_file(params[:file][:filename])
  end
  redirect to ('/')
end

post '/remove_track' do
  Track.destroy_from_title(params[:name])
end

post "/say" do
  if params[:audio_files]
    params[:audio_files].each do |audio_file|
     `aplay "#{File.join(File.dirname(__FILE__), "public", audio_file)}"` #aplay ne lit pas les mp3
   end
 end
 redirect to ('/')
end

post '/doing' do
  Robot.new.send(params[:what])
  redirect to ('/')
end

post '/sort_url' do
  params[:tracks].each do |index, track|
    Track.find_by(title: track["title"]).update position: index
  end
end

post '/vote' do
  redis = REDIS_VOTES
  if redis.get("demarrer") == "off"
    remettre_a_zero(redis)
    redis.hset "votes", "track1", "#{params[:hash1]}"
    redis.hset "votes", "track2", "#{params[:hash2]}"
    redis.hset "votes", "track3", "#{params[:hash3]}"
    redis.set "demarrer", "on"
    return 'Arrêter'
  else
    redis.set "demarrer", "off"
    return 'Démarrer'
  end
end

get "/update_vote" do
  redis = REDIS_VOTES
  if redis.get("demarrer") == "off"
    "stop polling".to_json
  else
    {vote_1: redis.hget("votes", "counter1"),
      vote_2: redis.hget("votes", "counter2"),
      vote_3: redis.hget("votes", "counter3")}.to_json
    end
  end

  post "/remettre_a_zero" do
    redis = REDIS_VOTES
    remettre_a_zero(redis)
  end