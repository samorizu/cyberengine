#!/usr/bin/env ruby
require_relative '../cyberengine/cyberengine'
log = File.dirname(__FILE__) + '/../logs/ipv4/smtp-send-mail.log'
@cyberengine = Cyberengine.new(STDOUT,log) 


@services = @cyberengine.services('SMTP Send Mail','ipv4','smtp')
@defaults = @cyberengine.defaults('SMTP Send Mail','ipv4','smtp')


def build_request(service,address)
  # -s Silent or quiet mode. Dont show progress meter or error messages.  Makes Curl mute.
  # -S When used with -s it makes curl show an error message if it fails.
  # -4 Resolve names to IPv4 addresses only
  # -v Verbose mode. '>' means sent data. '<' means received data. '*' means additional info provided by curl
  # --mail-from Source mail address user@domain
  # --mail-rcpt Destination mail address user@domain
  request = 'curl -s -S -4 -v '

  # From User
  from_user = service.properties.random('from-user') 
  from_user = service.users.random unless from_user
  raise "Missing users" unless from_user 
  from_username = from_user.username.url_encode
  from_password = from_user.password.url_encode

  # From Domain
  from_domain = service.properties.option('from-domain') 
  raise("Missing from-domain property") unless from_domain
  from_domain = from_domain.url_encode

  # Add From Email
  request << " --mail-from '#{from_username}'@'#{from_domain}' "

  # Rcpt User
  rcpt_user = service.properties.random('rcpt-user') 
  rcpt_user = service.users.random unless rcpt_user
  raise "Missing users" unless rcpt_user 
  rcpt_username = rcpt_user.username.url_encode

  # Rcpt Domain
  rcpt_domain = service.properties.option('rcpt-domain') 
  raise("Missing rcpt-domain property") unless rcpt_domain
  rcpt_domain = rcpt_domain.url_encode

  # Add Rcpt Email
  request << " --mail-rcpt '#{rcpt_username}'@'#{rcpt_domain}' "

  # Each line regex match
  @each_line_regex = service.properties.answer('each-line-regex') || @defaults.properties.answer('each-line-regex')
  @full_text_regex = service.properties.answer('full-text-regex') || @defaults.properties.answer('full-text-regex')
  raise "Missing answer property: each-line-regex or full-text-regex required" unless @each_line_regex || @full_text_regex

  # Mail gets text from STDIN
  request.prepend("echo 'cyberengine check' | ")
  request << ' -T - '

  # URL
  request << " smtp://#{from_username}:#{from_password}@#{address}"

  # Return request single spaced and without leading/ending spaces
  request.strip.squeeze(' ')
end


# Determine if check passed 
def parse_response(response)
  passed = false
  if @each_line_regex
    begin @each_line_regex = Regexp.new(@each_line_regex) rescue raise("Invalid each-line-regex: #{@each_line_regex}") end
    response.each_line do |line|
      passed = true if line =~ @each_line_regex
    end
  end
  if @full_text_regex
    begin @full_text_regex = Regexp.new(@full_text_regex) rescue raise("Invalid full-text-regex: #{@each_line_regex}") end
    passed = true if response =~ @full_text_regex
  end
  passed
end


@services.each do |service|
  service.properties.addresses.each do |address|
    # Mark start of check in log
    @cyberengine.logger.info { "Starting check - Team: #{service.team.alias} - Server: #{service.server.name} - Service: #{service.name} - Address: #{address}" }

    begin
      # Request command
      request = build_request(service,address) 

      # Get request output
      response = @cyberengine.shellcommand(request,service,@defaults)

      # Passed: true/false
      passed = parse_response(response) 

      # Save check and get result
      round = service.checks.next_round
      check = @cyberengine.create_check(service,round,passed,request,response) 

      # Check for errors in saving check 
      raise check.errors.full_messages.join(',') if check.errors.any?

      # Mark end of check in log
      result = passed ? 'Passed' : 'Failed'
      @cyberengine.logger.info { "Finished check - Team: #{service.team.alias} - Server: #{service.server.name} - Service: #{service.name} - Address: #{address} - Result: #{result}" }

    rescue Exception => exception
      @cyberengine.exception_handler(service,exception)
    end
  end
end