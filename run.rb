
USAGE = 'ruby run.rb [CMD] where [CMD] is:
  list_texts:              Display list of texts currently loaded for sampling
  prebuild_tweets [COUNT]: Pre-build COUNT tweets and save in queue
  list_queued:             Display all tweets in data/queue
  delete_queued [KEY]:     Delete tweet from data/queue by key
  tweet!:                  Select a random tweet, dequeue it, and tweet it'

require 'stanford-core-nlp'
require 'open-uri'
require 'csv'
require 'digest'
require 'json'
require 'filecache'
require 'twitter'

class PrepBot

  BLACKLISTED_TERMS = ['nig' + 'ger', '`']
  TWEET_QUEUE_BASE = "./data/queued"
  TWEET_USED_BASE = "./data/used"

  def delete_queued(key)
    `rm #{TWEET_QUEUE_BASE}/#{key}.json`
  end

  def tweet!
    tweet = get_queued.sample(1).first
    puts "Tweeting: #{tweet.to_s}"
    client.update tweet.to_s
    dequeue tweet
  end

  def list_queued
    puts "Queued tweets: "
    get_queued.each do |tweet|
      puts tweet.to_s
      puts "__ id #{tweet.cache_key} __________________________________"
      puts ""
    end
  end

  def prebuild_tweets(count)
    count.times do
      path = nil
      tweet = nil
      loop do
        tweet = select_tweet
        path = path_for(tweet)
        break if ! File.exist?(path)
      end
      File.open(path, 'w') do |file|
        file.write JSON.generate(tweet.to_h)
      end

      puts "Prebuild tweet: #{tweet.to_s}"
    end
  end

  def list_texts
    texts = get_texts
    puts "Texts:"
    texts.each do |text|
      len = load_text(text['URL']).size
      puts "  #{text['Title']}: #{len}"
    end
  end

  private

  def dequeue(tweet)
    puts "mv #{TWEET_QUEUE_BASE}/#{tweet.cache_key}.json #{TWEET_USED_BASE}/#{tweet.cache_key}.json"
    `mv #{TWEET_QUEUE_BASE}/#{tweet.cache_key}.json #{TWEET_USED_BASE}/#{tweet.cache_key}.json`
  end

  def client
    if ENV['TWITTER_CONSUMER_KEY'].nil? || ENV['TWITTER_CONSUMER_KEY'].empty?
      puts "Set Twitter ENV"
      exit
    end

    Twitter::REST::Client.new do |config|
      config.consumer_key        = ENV["TWITTER_CONSUMER_KEY"]
      config.consumer_secret     = ENV["TWITTER_CONSUMER_SECRET"]
      config.access_token        = ENV["TWITTER_ACCESS_TOKEN"]
      config.access_token_secret = ENV["TWITTER_ACCESS_SECRET"]
    end
  end

  def get_queued
    ret = []
    Dir.glob "#{TWEET_QUEUE_BASE}/*.json" do |file|
      h = JSON.parse File.read("#{file}")
      ret << Tweet.new(h)
    end
    ret
  end

  def path_for(tweet)
    "#{TWEET_QUEUE_BASE}/" + tweet.cache_key + ".json"
  end

  def select_tweet
    if false
      tweet = Tweet.new({
        title: 'Title of work',
        author: 'Author of work',
        text: 'tweeeety tweet'
      })
      return tweet
    end
    text = select_text

    preps = parse_prepositions text['text']
    candidates = []
    preps.each_with_index do |p, i|
      bad = false
      bad ||= p[:text].split(/\s/).size < 2
      bad ||= ( i > (preps.size - 2) )
      bad ||= p[:text].size > 40
      bad ||= p[:text].size < 10
      bad ||= BLACKLISTED_TERMS.include? p[:text]
      candidates << p if ! bad
    end
    if candidates.empty?
      puts "couldn't find a tweet from #{text['Title']}"
      exit
    end

    selection = candidates.sample(1).first
    tweet = Tweet.new({
      text: selection[:text],
      title:  text['Title'],
      author: text['Author'],
      cat_url: text['NYPL CAT URL'],
      text_url: text['URL'],
      original_text: text['text']
    })
    tweet
  end

  def select_text
    texts = get_texts
    # Todo: prevent randomly sampling any text too frequently; Select in a round maybe
    text = texts.sample(1).first
    text['text'] = sample_text load_text(text['URL'])
    text
  end

  def load_config(file)
    JSON.parse File.read("./config/#{file}.json")
  end

  def get_texts
    require 'open-uri'
    texts = CSV.parse open('https://docs.google.com/spreadsheets/d/1yYNNh3hcqhIWzFGI2Wv2Vdl_SuoY2S-xv23ElDAaMHA/pub?gid=0&single=true&output=csv'), headers:true
    texts = texts.select { |t| ! t['URL'].nil? && ! t['URL'].empty? }
    texts
  end

  def load_text(url, retries_remaining=0)
    @cache ||= FileCache.new 'texts',"./data/cache"

    text = @cache.get url
    if text.nil? || text.empty?
      text = nil
      puts "Fetching #{url}"
      begin
        open url do |f|
          text = f.read
        end
      rescue
        puts "WARN: Failed to load #{url}"
        return ''
      end
      puts " Saving to cache: #{text.size}"
      @cache.set url, text
      sleep rand((5..10))
    else
      puts " Read from cache: #{text.size}"
    end
    if text.size < 10000
      puts " Received captcha resp, retrying"
      @cache.delete url

      if retries_remaining > 0
        sleep 5
        text = load_text url, retries_remaining - 1
      end
    end
    text
  end

  def sample_text(text)
    len = 2000
    boilerplate_begin = 10000
    boilerplate_end = 20000
    rand_begin = boilerplate_begin
    rand_end = text.size - boilerplate_end - len
    puts "chose range: #{rand_begin} .. #{rand_end} for #{text.size}"
    text = text[rand((rand_begin..rand_end)), len]
    text
  end

  def parse_prepositions(text)

    # Use the model files for a different language than English.
    StanfordCoreNLP.use :english 
    StanfordCoreNLP.jar_path = ENV['CORENLP_PATH']
    StanfordCoreNLP.model_files = {}
    StanfordCoreNLP.default_jars = [
      'joda-time.jar',
      'xom.jar',
      'stanford-corenlp-3.7.0.jar',
      'stanford-corenlp-3.7.0-models.jar',
      'jollyday.jar',
      'bridge.jar'
    ]

    pipeline = StanfordCoreNLP.load(:tokenize, :ssplit, :pos, :lemma, :parse)
    text = StanfordCoreNLP::Annotation.new(text)
    pipeline.annotate(text)

    prepositions = []
    text.get(:sentences).each do |sentence|
      # Syntatical dependencies
      sentence.get(:tree).each do |tree|
        next if tree.children.empty?

        # If first child is a PP..
        tag = tree.value

        if tag == 'PP'
          text = flatten_tree tree

          text = text.gsub(/\s,/, ',')

          prepositions << {
            text: text
          }
        end

      end
    end
    prepositions
  end

  def flatten_tree(tree)
    if tree.label.get(:category).to_s == ''
      tree.to_s
    else
      tree.children.map { |t| flatten_tree t }.join ' '
    end
  end
end

class Tweet
  attr_accessor :text, :original_text, :title, :author, :text_url, :cat_url

  def initialize(h)
    for k in h.keys
      send "#{k}=", h[k] if self.respond_to? "#{k}="
    end
  end

  def to_h
    {
      text: encode_utf8(text),
      original_text: encode_utf8(original_text),
      title: encode_utf8(title),
      author: encode_utf8(author),
      cat_url: cat_url
    }
  end

  def to_s
    lines = ["\"#{text}\"", "#{title}", "#{author}"]
    lines << cat_url if cat_url
    lines << "[#{text_url}]" if text_url
    lines.join "\n"
  end

  def cache_key
    Digest::MD5.hexdigest(text)
  end
end

def encode_utf8(str)
  str.encode('UTF-8', {
    :invalid => :replace,
    :undef   => :replace,
    :replace => '?'
  })
end

def show_help
  puts "Usage:\n#{USAGE}"
end

bot = PrepBot.new
if (ARGV.empty? || !bot.methods.include?(ARGV.first.to_sym))
  show_help
  exit
end

command = ARGV.first
if bot.respond_to? command
  args = ARGV.map { |v| v.match(/^[0-9]+$/) ? v.to_i : v }
  bot.send(*args)
else
  puts "Invalid command."
  show_help
end
