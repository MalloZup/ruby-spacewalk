module XMLRPC
  class Client
    def get_parser
      parser
    end
  end
end

module Spacewalk
  class Server
    # from /usr/sbin/rhn_check
    # action version we understand
    ACTION_VERSION = 2 

    require "xmlrpc/client"
    require 'uri'
    require 'zlib'
    require 'base64'
    require 'rexml/document'

private
    def call name, *args
      puts "Call #{name}(#{args.inspect})"
      begin
	result = @client.call(name, *args)
      rescue Exception => e
	raise e unless e.message =~ /Wrong content-type/
      end
      response = @client.http_last_response
      raise "XMLRPC failed with #{response.code}" unless response.code == "200"
      body = response.body
      case response["content-type"]
      when "text/base64"
	body = Base64.decode64(body)
      when "text/xml"
	# fallthru
      else
        STDERR.puts "Unhandled content-type #{response['content-type']}"	
      end
      case response["content-encoding"]
      when "x-zlib"
	body = Zlib::Inflate.inflate(body)
      when nil
	# fallthru
      else
	STDERR.puts "Unhandled content-encoding #{response['content-encoding']}"
      end
      ok, result = @client.get_parser.parseMethodResponse(body)
      raise unless ok
      result
    end
public

    #
    # Initialize server xmlrpc port
    # options:
    #  :noconfig => true - don't load @config
    #  :server => string - url of server (for initial registration)
    #
    def initialize options = {}
      @config = Spacewalk::Config.new
      if options[:noconfig]
	uri = URI.parse(options[:server])
	uri.path = "/XMLRPC"
      else
	uri = URI.parse(@config.serverurl)
      end

      args = {:host=>uri.host, :path => uri.path, :use_ssl => (uri.scheme == "https")}

      unless options[:noconfig]
	if @config.httpProxy
	  args[:proxy_host], clientargs[:proxy_port] = @config.httpProxy.split ":"
	end
      end

      @client = XMLRPC::Client.new_from_hash args

      @client.http_header_extra = {}

      welcome

      # parse server capabilities
      @capabilities = Spacewalk::Capabilities.new @client
			      
      @client.http_header_extra["X-Up2date-Version"] = "1.6.42" # from rhn-client-tools.spec
				  
      unless options[:noconfig]
	@systemid = Spacewalk::SystemId.new @client, @config
      end
      # check for distribution update
#      my_id = @systemid.os_release
#      server_id = osversion

    end
    
    # welcome to/from server
    def welcome
      result = call "registration.welcome_message"
      puts "Welcome => #{result.inspect}"
    end
    
    # get system O/S version
    def osversion
      result = @config.versionOverride
      unless result
	# find rpm provider of redhat-release or distribution-release, get its version
      end
      result
    end
    
    def actions
      report = Spacewalk::StatusReport.status

      result = call "queue.get", @systemid.to_xml, ACTION_VERSION, report
      puts "Actions => #{result.inspect}"
      
      if action = result["action"]
	result["action"] = @client.get_parser.parseMethodCall(action)
      end      
      puts "Actions => #{result.inspect}"
    end
    
    def register activationkey, profile_name, other = {}, packages = nil
      auth_dict = {}
      auth_dict["profile_name"] = profile_name
      #"os_release" : up2dateUtils.getVersion(),
      #"release_name" : up2dateUtils.getOSRelease(),
      #"architecture" : up2dateUtils.getArch() }
      # dict of other bits to send 
      auth_dict.update other
      auth_dict["token"] = activationkey
      # auth_dict["username"] = username
      # auth_dict["password"] = password

      # if cfg['supportsSMBIOS']:
      #	auth_dict["smbios"] = _encode_characters(hardware.get_smbios())
      STDERR.puts "registration.new_system #{auth_dict.inspect}"
      call "registration.new_system", auth_dict, packages
    end
  end
end
