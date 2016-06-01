defmodule Hedwig.Adapters.Flowdock.StreamingConnectionTest do
  import Hedwig.Adapters.Flowdock.StreamingConnection

  use ExUnit.Case
  doctest Hedwig.Adapters.Flowdock.StreamingConnection

  @sample_flow_response %{
                            "access_mode" => "invitation",
                            "api_token" => "1f3f5aad4e9bb66319ab0554ee660dc0",
                            "description" => "Discussion amongst distributed nutjobs",
                            "email" => "pwd-whoami@pwd-whoami.flowdock.com",
                            "flow_admin" => true,
                            "id" => "3d14e900-977d-49af-a7ec-64aaf142bba6",
                            "joined" => true,
                            "last_message_at" => "2016-06-01T05:05:21.471Z",
                            "last_message_id" => 494281,
                            "name" => "pwd/whoami",
                            "open" => true,
                            "organization" => %{
                              "active" => true,
                              "flow_admins" => false,
                              "id" => 44373,
                              "name" => "pwd && whoami",
                              "parameterized_name" => "pwd-whoami",
                              "url" => "https://api.flowdock.com/organizations/pwd-whoami",
                              "user_count" => 5,
                              "user_limit" => 5
                            },
                            "parameterized_name" => "pwd-whoami",
                            "team_notifications" => true,
                            "url" => "https://api.flowdock.com/flows/pwd-whoami/pwd-whoami",
                            "web_url" => "https://www.flowdock.com/app/pwd-whoami/pwd-whoami"
                         }

  test "paramaterize_flows" do
    assert parameterize_flows([@sample_flow_response]) == "pwd-whoami/pwd-whoami"
    assert parameterize_flows([@sample_flow_response, @sample_flow_response]) == "pwd-whoami/pwd-whoami,pwd-whoami/pwd-whoami"
  end
end
