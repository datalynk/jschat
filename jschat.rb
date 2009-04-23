require 'rubygems'
require 'eventmachine'
require 'json'

module JsChat
  class User
    attr_accessor :name, :connection

    def initialize(connection)
      @name = nil
      @connection = connection
    end

    def to_json
      { 'name' => @name }.to_json
    end

    def name=(name)
      if valid_name? name
        @name = name
      else
        raise JsChat::Errors::InvalidName.new('Invalid name')
      end
    end

    def valid_name?(name)
      not name.match /[^[:alnum:]._\-\[\]^C]/
    end

    def private_message(message, from)
    end
  end

  class Room
    attr_accessor :name, :users

    def initialize(name)
      @name = name
      @users = []
    end

    def self.find(item)
      @@rooms ||= []

      if item.kind_of? String
        @@rooms.find { |room| room.name == item }
      elsif item.kind_of? User
        @@rooms.find_all { |room| room.users.include? item }
      end
    end

    def self.find_or_create(room_name)
      room = find room_name
      if room.nil?
        room = new(room_name)
        @@rooms << room
      end
      room
    end

    def join(user)
      if users.find { |u| u == user }
        Error.new('Already in that room').to_json
      else
        users << user
        join_notice user
        { 'joined' => self }.to_json
      end
    end

    def send_message(message)
      message['room'] = name

      @users.each do |user|
        user.connection.send_data message.to_json + "\n"
      end
    end
    
    def member_names
      @users.collect { |user| user.name }
    end

    def to_json
      { 'name' => @name, 'members' => member_names }.to_json
    end

    def join_notice(join_user)
      @users.each do |user|
        if user != join_user
          user.connection.send_data({ 'user' => join_user.name, 'joined' => @name }.to_json + "\n")
        end
      end
    end

    def quit_notice(quit_user)
      @users.each do |user|
        if user != quit_user
          user.connection.send_data({ 'quit' => quit_user.name, 'from' => @name }.to_json + "\n")
        end
      end
      @users.delete_if { |user| user == quit_user }
    end
  end

  class Error < RuntimeError
    def to_json
      { 'error' => message }.to_json
    end
  end

  module Errors
    class InvalidName < JsChat::Error
    end
  end

  # {"identify":"alex"}
  def identify(name, options = {})
    if @@users.find { |user| user.name == name }
      Error.new("Nick already taken").to_json
    else
      @user.name = name
      @user.to_json
    end
  rescue JsChat::Errors::InvalidName => exception
    exception.to_json
  end

  def change(operator, options)
  end

  # {"to"=>"#merk", "send"=>"hello"}
  def send_message(message, options)
    room = Room.find options['to']
    room.send_message({ 'message' => message, 'user' => @user.name })
  end

  # {"join":"#merk"}
  def join(room_name, options = {})
    room = Room.find_or_create(room_name)
    room.join(@user)
  end

  # {"names":"#channel"}
  def names(room_name, options = {})
    room = Room.find(room_name)
    if room
      { 'names' => room.users.collect { |user| user.name } }.to_json
    else
      Error.new('No such room').to_json
    end
  end

  def unbind
    # TODO: Remove user from rooms and remove connection
    puts "Removing a connection"
    Room.find(@user).each do |room|
      room.quit_notice @user
    end

    @@users.delete_if { |user| user == @user }
    @user = nil
  end

  def post_init
    @@users ||= []
    @user = User.new(self)
    @@users << @user
  end

  def receive_data(data)
    # Receive the identify request
    input = JSON.parse data

    if input.has_key? 'identify'
      send_data identify(input['identify']) + "\n"
    else
      ['change', 'send', 'join', 'names'].each do |command|
        if @user.name.nil?
          return send_data(Error.new("Identify first").to_json + "\n")
        end

        if input.has_key? command
          if command == 'send'
            return send('send_message', input[command], input)
          else
            return send_data(send(command, input[command], input) + "\n")
          end
        end
      end
    end
  rescue Exception => exception
    puts exception
  end
end

