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

# one-time configuration of mqlight client
configure do
  SUBSCRIBE_TOPIC = 'mqlight/sample/wordsuppercase'
  PUBLISH_TOPIC = 'mqlight/sample/words'
  SHARE_ID = 'ruby-front-end'
  mqlight_service_name = 'mqlight'
  messagehub_service_name = 'messagehub'

  opts = { id: "sinatra_frontend_#{SecureRandom.hex[0..6]}" }

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
        uri = messagehub_service['credentials']['connectionLookupURI']
        opts[:user] = messagehub_service['credentials']['user']
        opts[:password] = messagehub_service['credentials']['password']
      end
    end
  else
    uri = 'amqp://127.0.0.1:5672'
  end

  set :client, Mqlight::BlockingClient.new(uri, opts)
  settings.client.subscribe(SUBSCRIBE_TOPIC, share: SHARE_ID)
  set :recv_queue, Queue.new
  set :send_queue, Queue.new

  Thread.new do

    loop do
      delivery = settings.client.receive(SUBSCRIBE_TOPIC, share: SHARE_ID,
                                                          timeout: 1000)
      if delivery
        puts "Received delivery: #{delivery}"
        data = JSON.parse(delivery.data)
        settings.recv_queue.push(data: data, delivery: delivery)
      end

      next unless settings.send_queue

      until settings.send_queue.empty?
        params = settings.send_queue.pop(true)
        settings.client.send(params[:topic], params[:message])
      end
    end
  end
end

# POST handler to publish words to our topic
post '/rest/words' do
  request.body.rewind
  request_payload = JSON.parse request.body.read

  # check they've sent { "words" : "some sentence" }
  halt 500, 'No words' unless request_payload['words']

  # split it up into words
  msg_count = 0
  request_payload['words'].split(' ').each do |word|
    # send it as a message
    message = { word: word, frontend: "Ruby: #{settings.client.id}" }
    puts "Sending response: #{message}"
    settings.send_queue.push(topic: PUBLISH_TOPIC,
                             message: JSON.unparse(message))
    msg_count += 1
    # send back a count of messages sent
    body(JSON.unparse(msgCount: msg_count))
  end
end

# GET handler to poll for notifications
get '/rest/wordsuppercase' do
  # do we have a message held?
  if settings.recv_queue.empty?
    # just return no-data
    204
  else
    # send the data to the caller
    params = settings.recv_queue.pop(true)
    headers 'Content-Type' => 'application/json'
    body JSON.unparse(params[:data])
  end
end

# GET handler for any static content
set :public_folder, 'static'

# GET handler for root / redirect
get '/' do
  redirect '/index.html'
end
