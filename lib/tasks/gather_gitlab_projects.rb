module Intrigue
  module Task
    class GatherGitlabProjects < BaseTask
      def self.metadata
        {
          name: 'gather_gitlab_projects',
          pretty_name: 'Gather Gitlab Projects',
          authors: ['maxim'],
          description: 'Uses the Gitlab API to pull all known repositories for a GitlabAccount.',
          references: ['https://docs.gitlab.com/ee/api/'],
          type: 'discovery',
          passive: false,
          allowed_types: ['GitlabAccount'],
          example_entities: [{ 'type' => 'GitlabAccount', 'details' => { 'name' => 'https://gitlab.intrigue.io/account' } }],
          allowed_options: [],
          created_types: ['GitlabProject']
        }
      end

      ## Default method, subclasses must override this
      def run
        super
        
        parameters = _create_parameters_from_gitlab_uri
        return if parameters.nil?

        parameters['access_token'] = retrieve_gitlab_token(parameters['host']) || ''

        projects = gather_gitlab_projects(parameters)
        _log "Gathered #{projects.size} projects!"
        return if projects.empty?

        projects.each { |r| _create_entity('GitlabProject', { 'name' => "#{host}/#{r}" }) }
      end

      def _create_parameters_from_gitlab_uri
        parsed_uri = parse_gitlab_uri(_get_entity_name, 'account')
        parsed_uri['account'].gsub!('/', '%2f') # urlencode / if its a project name

        if [parsed_uri['host'], parsed_uri['account']].include?(nil) 
          _log_error 'Error parsing Gitlab Account; ensure the format is \'https://gitlab.intrigue.io/username\''
          return
        end

        parsed_uri
      end

      def gather_gitlab_projects(parameters_h)
        results = []
        access_token = parameters_h['access_token']
        headers = { 'PRIVATE-TOKEN' => access_token } if access_token
        uri = _generate_gitlab_api_uri(parameters_h['host'], parameters_h['account'], access_token)

        page = 1
        loop do
          _log "Getting results from Page #{page}"
          r = http_request(:get, "#{uri}?page=#{page}&per_page=100&simple=true", nil, headers)
          break if r.body.empty? || r.body.nil? || r.code.to_i.zero?

          break if api_request_limit_exhausted?(r) # exhausted total number of requests

          parsed_response = _parse_json_response(r.body)
          break if parsed_response.nil?

          results << parsed_response&.map { |j| j['web_url'] } # in case any random response returned; use safe nil nav
        end

        projects.flatten.compact
      end

      def api_request_limit_exhausted?(response)
        exhausted = response.headers['RateLimit-Remaining']&.eql?('0')
        _log_error 'Request limited exhausted; aborting task.' if exhausted

        exhausted
      end

      def _generate_gitlab_api_uri(host, account, access_token)
        if is_gitlab_group?(host, account, access_token)
          "#{host}/api/v4/groups/#{account}/projects"
        else
          "#{host}/api/v4/users/#{account}/projects"
        end
      end

      def _parse_json_response(response)
        JSON.parse(response)
      rescue JSON::ParserError
        _log_error 'Unable to parse JSON'
      end

    end
  end
end
