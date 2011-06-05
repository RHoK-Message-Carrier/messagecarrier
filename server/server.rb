#!/usr/bin/ruby

require 'sinatra'
require 'sinatra/reloader' if development?
require './database'

require 'net/http'
require 'builder'
require 'twiliolib'
require 'yajl'
require "uri"
require "json"
require 'net/smtp'
require 'twitter'
require './ushahidi_controller'
require './hv'

API_VERSION = '2010-04-01'
ACCOUNT_SID = 'AC8e8905f38869781042ee40212be175eb'
ACCOUNT_TOKEN = '2e3211a8848b2220d93e4aa31f89d899'
CALLER_ID = '+16478384390'

Twitter.configure do |config|
  config.consumer_key = ''
  config.consumer_secret = ''
  config.oauth_token = ''
  config.oauth_token_secret = ''
end


get "/" do
  erb :index
end

get "/edit" do
  erb :edit
end

post "/update" do
  #stuff 
end

post "/messages" do
  content_type :json
  statuses = { }
  messages = Yajl::Parser.parse(request.body.read)
  unless messages.is_a?(Array)
    messages = [messages]
  end
  messages.each do |msg|
    begin
      if database[:messages].where(:messageid => msg['messageid']).first
        statuses[msg['messageid']] = :existing
      else
        if database[:messages].insert(msg)
          if msg['messagetype'].to_i == 0
            send_sms(msg)
          elsif msg['messagetype'].to_i == 1
            send_email(msg)
          elsif msg['messagetype'].to_i == 2
            send_twitter(msg)
          else
            # TODO: handle unknown message types
          end
          statuses[msg['messageid']] = :accepted

          if msg['personstatus'].to_i == 0 #A-OK
            send_ushahidi(msg);
          elsif msg['personstatus'].to_i == 1 #HELP
            send_ushahidi(msg);
          elsif msg['personstatus'].to_i == 2 #Private
            #do NOT send to ushahidi!
          else
            #unknown person status
          end

        else
          puts "DB error"
          statuses[msg['messageid']] = :error
        end
      end
    rescue Exception => e
      puts e.inspect
      statuses[msg['messageid']] = :error
    end
  end
  Yajl::Encoder.encode(statuses)

end

helpers do
  def format_text(msg)
    "Emergency msg: #{msg['messagebody']}"
  end


  
  def send_sms(msg)
    t = {
      'From' => CALLER_ID,
      'To' => msg['destination'],			
      'Body' => format_text(msg)
    }
    begin
      account = Twilio::RestAccount.new(ACCOUNT_SID, ACCOUNT_TOKEN)
      resp = account.request("/#{API_VERSION}/Accounts/#{ACCOUNT_SID}/SMS/Messages",
                             'POST',
                             t)
    ensure
      puts "Twilio Response: " + resp.body
    end
    resp.error! unless resp.kind_of? Net::HTTPSuccess
    puts "code: %s\nbody: %s" % [resp.code, resp.body]
    true # TODO: handle errors
  end

  def send_email(msg)
    from = 'messagecarrier@lavabit.com'
    to = msg['destination']
    smtp_host   = 'lavabit.com'
    smtp_port   = 25
    smtp_domain = 'lavabit.com'
    smtp_user   = 'messagecarrier2'
    smtp_pwd    = 'rh0kATL'
    
    subject = "[MessageCarrier] Emergency Message"
    time = Time.now
    emaildate = time.strftime("%a, %d %b %Y %H:%M:%S -0400")
    
    #Compose the message for the email
    emailmsg = <<END_OF_MESSAGE
Date: #{emaildate}
From: #{from}
To: #{to}
Subject: #{subject}

You have received a message from an
area experiencing a communications emergency:

  #{msg['messagebody']}

Please don't reply to this email, it will not be delivered.
END_OF_MESSAGE

    Net::SMTP.start(smtp_host, smtp_port, smtp_domain, smtp_user, smtp_pwd, :plain) do |smtp|
      smtp.send_message emailmsg, from, to
    end
  end

  def send_twitter(msg)
    latlong = msg['location'].split(',')
    Twitter.update(msg['messagebody'], {"lat" => latlong[0], "long" => latlong[1], "display_coordinates" => "true"})
    #Twitter.update(format_text(msg))
  end

  def send_ushahidi(msg)
   latlong = msg['location'].split(',') 
   url_to_use = get_u_servers(latlon)
   sendStuff = create_sendStuff_msg(msg, foo)
   url_to_use.each do |url|
      res = Net::HTTP.post_form(URI.parse(url))
      res["content-type"] = "application/json"
      res.body = sendStuff.to_json
      request(res)
    end
    
   end
  end
  
  def create_sendStuff_msg(msg, foo_num)
    foo = case foo_num
      when 1
        "Something"
      when 2
         "Something"
      when 5
         "Something"
      when 6
         "Something"
      else
        "default"
      
      end
      t = Time.now
     sendStuff = Hash.new
     sendStuff[:task] = "report"
     sendStuff[:incident_title] = "#{foo} Emergency Message"
     sendStuff[:incident_date] = t.mon.to_s + "/" + t.day.to_s + "/" + t.year.to_s
     sendStuff[:incident_hour] = t.hour
     sendStuff[:incident_minute] = t.min
     sendStuff[:incident_ampm] = "report"
     sendStuff[:incident_category] = 5
     latlon = msg['location'].split(',')
     sendStuff[:latitude] = latlon.first
     sendStuff[:longitude] = latlon.last
     sendStuff[:location_name] = "report"
     sendStuff
  end
  
  
  
  def get_u_servers(latlon)
    db = Sequel.sqlite('messagecarrier.db')
    dataset = db[:ushahidi]
    urls = []
    dataset.each do |u|
      lat = u[:lat]
      lon = u[:lon]
      #check distance
      haversine_distance(lat,lon,  latlon.first, latlon.last ) 
      if @distance["km"] < u[:radius]
        urls << u[:url]
       
      end  
    end
    return urls
  
  end
