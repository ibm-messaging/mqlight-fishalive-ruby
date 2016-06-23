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
  SHARE_ID = "fishalive-workers"
  mqlight_service_name = 'mqlight'
  messagehub_service_name = 'messagehub'

  opts = { id: "sinatra_backend_#{SecureRandom.hex[0..6]}" }

  if ENV['VCAP_SERVICES']
    vcap_services = JSON.parse(ENV['VCAP_SERVICES'])
    for service in vcap_services.keys
      if service.start_with?(mqlight_service_name)
        mqlight_service = vcap_services[service][0]
        uri = mqlight_service['credentials']['nonTLSConnectionLookupURI']
        opts[:user] = mqlight_service['credentials']['username']
        opts[:password] = mqlight_service['credentials']['password']
      elsif service.start_with?(messagehub_service_name)
        messagehub_service = vcap_services[service][0]
        uri = messagehub_service['credentials']['mqlight_lookup_url']
        opts[:user] = messagehub_service['credentials']['user']
        opts[:password] = messagehub_service['credentials']['password']
      end
    end
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
