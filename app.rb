require "sinatra"
require "sinatra/reloader"
require "sinatra/cookies"
require "http"
require "uri"
require "net/http"
require "json"
require "openai"

use Rack::Session::Cookie, :key => "rack.session",
                           :path => "/",
                           :secret => ENV.fetch("SESSION_SECRET")

state_initials_array = ["AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"]

get("/") do
  state_initials_sample = state_initials_array.sample

  bird_api = ENV.fetch("BIRD_API")
  bird_url = URI("https://api.ebird.org/v2/data/obs/US-#{state_initials_sample}/recent")

  https = Net::HTTP.new(bird_url.host, bird_url.port)
  https.use_ssl = true

  request = Net::HTTP::Get.new(bird_url)
  request["X-eBirdApiToken"] = "#{bird_api}"

  response = https.request(request)

  res_body = response.read_body
  parsed_res_body = JSON.parse(res_body)

  hashes_array = []

  parsed_res_body.each do |hash|
    hashes_array.push(hash)
  end

  hash_sample = hashes_array.sample

  @latin_name_sample = hash_sample["sciName"]
  @common_name_sample = hash_sample["comName"]
  @latitude_sample = hash_sample["lat"]
  @longitude_sample = hash_sample["lng"]

  session[:latin_name] = @latin_name_sample
  session[:common_name] = @common_name_sample
  session[:lat] = @latitude_sample
  session[:lng] = @longitude_sample

  erb(:homepage)
end

post("/dalle") do
  @latin_name_sample = session[:latin_name]
  @latin_name_no_space = @latin_name_sample.gsub(" ", "+")

  # Open AI
  future_key = ENV.fetch("FUTURE_KEY")

  OpenAI.configure do |config|
    config.access_token = future_key
  end

  client = OpenAI::Client.new

  response = client.chat(
    parameters: {
      model: "gpt-3.5-turbo",
      messages: [{ role: "user", content: @latin_name_no_space }],
      temperature: 0.7,
    },
  )

  response_dalle = client.images.generate(parameters: { prompt: @latin_name_no_space, size: "256x256" })
  image_data = response_dalle.fetch("data")
  image_first = image_data[0]
  @image_url = image_first.fetch("url")

  session[:image] = @image_url

  erb(:dalle)
end

post("/location") do
  @latin_name_sample = session[:latin_name]
  @image_url = session[:image]

  @latitude_sample = session[:lat]
  @longitude_sample = session[:lng]

  gmaps_key = ENV.fetch("GMAPS_KEY")
  gmaps_url = "https://maps.googleapis.com/maps/api/geocode/json?latlng=#{@latitude_sample},#{@longitude_sample}&key=#{gmaps_key}"

  raw_gmaps_data = HTTP.get(gmaps_url)
  parsed_gmaps_data = JSON.parse(raw_gmaps_data)
  results_array = parsed_gmaps_data.fetch("results")
  first_result_hash = results_array.at(0)
  address_components_hash = first_result_hash.fetch("address_components")

  address_components_array = []

  address_components_hash.each do |components|
    address_components_array.push(components)
  end

  matching_hash = address_components_array.find do |match|
    state_initials_array.include?(match.fetch("short_name"))
  end

  if matching_hash
    @state_name = matching_hash["long_name"]
    session[:state] = @state_name
  else
    puts "No matching hash found."
  end

  erb(:location)
end

post("/bird_name") do
  @latin_name_sample = session[:latin_name]
  @image_url = session[:image]
  @state_name = session[:state]

  @common_name = session[:common_name]

  erb(:common_name)
end

post("/bird_info") do
  @image_url = session[:image]
  @state_name = session[:state]
  @common_name = session[:common_name]

  @latin_name_sample = session[:latin_name]
  @latin_name_no_space = @latin_name_sample.gsub(" ", "+")

  # Open AI
  future_key = ENV.fetch("FUTURE_KEY")

  OpenAI.configure do |config|
    config.access_token = future_key
  end

  client = OpenAI::Client.new

  response = client.chat(
    parameters: {
      model: "gpt-3.5-turbo",
      messages: [{ role: "user", content: @latin_name_no_space }],
      temperature: 0.7,
    },
  )

  choices = response.fetch("choices")
  choice = choices[0]
  message = choice.fetch("message")
  @chat_gpt = message.fetch("content")

  session[:chat_gpt] = @chat_gpt

  erb(:bird_info)
end
