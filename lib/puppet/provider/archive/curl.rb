require 'uri'
require 'tempfile'

Puppet::Type.type(:archive).provide(:curl, parent: :ruby) do
  commands curl: 'curl'
  defaultfor feature: :posix

  def curl_params(params)
    if resource[:username]
      if resource[:username] =~ %r{\s} || resource[:password] =~ %r{\s}
        Puppet.warning('Username or password contains a space.  Unable to use netrc file to hide credentials')
        account = [resource[:username], resource[:password]].compact.join(':')
        params += optional_switch(account, ['--user', '%s'])
      else
        create_netrcfile
        params += ['--netrc-file', @netrc_file.path]
      end
    end
    params += optional_switch(resource[:proxy_server], ['--proxy', '%s'])
    params += ['--insecure'] if resource[:allow_insecure]
    params += resource[:download_options] if resource[:download_options]
    params += optional_switch(resource[:cookie], ['--cookie', '%s'])

    params
  end

  def create_netrcfile
    @netrc_file = Tempfile.new('.puppet_archive_curl')
    machine = URI.parse(resource[:source]).host
    @netrc_file.write("machine #{machine}\nlogin #{resource[:username]}\npassword #{resource[:password]}\n")
    @netrc_file.close
  end

  def delete_netrcfile
    return if @netrc_file.nil?

    @netrc_file.unlink
    @netrc_file = nil
  end

  def download(filepath)
    params_default = curl_params(
      [
        resource[:source],
        '-o',
        filepath,
        '-fsSLg',
        '--max-redirs',
        5
      ]
    )

    # optional header switch to use tokens, etc
    params_header = [
      optional_switch(resource[:header], ['-H', '%s'])
    ]
    
    # when header(s) defined, place header as the first param to the curl command
    unless resource[:header].nil?
      params_combined = params_header + params_default
    else
      params_combined = params_default
    end

    params = curl_params(params_combined)

    begin
      curl(params)
    ensure
      delete_netrcfile
    end
  end

  def remote_checksum
    params = curl_params(
      [
        resource[:checksum_url],
        '-fsSLg',
        '--max-redirs',
        5
      ]
    )

    begin
      curl(params)[%r{\b[\da-f]{32,128}\b}i]
    ensure
      delete_netrcfile
    end
  end
end
