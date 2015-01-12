# Copyright (c) 2014 IBM Corporation.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html
#
# Contributors:
# IBM - initial implementation

require 'sinatra'
require 'mqlight'
require 'securerandom'

configure do
  SUBSCRIBE_TOPIC = 'mqlight/sample/words'
  PUBLISH_TOPIC = 'mqlight/sample/wordsuppercase'
  SHARE_ID = 'ruby-back-end'

  opts = { id: "sinatra_backend_#{SecureRandom.hex[0..6]}" }

  if ENV['VCAP_SERVICES']
    vcap_services = JSON.parse(ENV['VCAP_SERVICES'])
    mqlight_service_name = 'mqlight'
    mqlight_service = vcap_services[mqlight_service_name]
    credentials = mqlight_service.first['credentials']
    uri = credentials['connectionLookupURI']
    opts[:user] = credentials['username']
    opts[:password] = credentials['password']
  else
    uri = 'amqp://127.0.0.1:5672'
  end

  set :client, Mqlight::BlockingClient.new(uri, opts)
  settings.client.subscribe(SUBSCRIBE_TOPIC, share: SHARE_ID)

  #
  def process_message(data)
    word = JSON.parse(data)['word']
    unless word
      $stderr.puts "Bad data received: #{data}"
      return
    end

    # upper case it and publish a notification
    reply_data = {
      word: word.upcase,
      backend: "Ruby: #{settings.client.id}"
    }
    send_reply(JSON.unparse(reply_data))
  end

  #
  def send_reply(message)
    puts "Sending response: #{message}"
    settings.client.send(PUBLISH_TOPIC, message)
  end

  Thread.new do
    loop do
      delivery = settings.client.receive(SUBSCRIBE_TOPIC, share: SHARE_ID,
                                                          timeout: 1000)
      next unless delivery
      process_message(delivery.data)
    end
  end
end

get '/' do
  "sinatra-recv: connected to #{settings.client.service}"
end
