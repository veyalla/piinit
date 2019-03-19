{
  prov_consulclient(hcl)::
      [
        {
          "type": "file",
          "source": hcl,
          "destination": "/opt/consul/config/client.hcl"
        },
        {
          "type": "shell",
          "inline": ["chown consul.consul /opt/consul/config/client.hcl"]
        },
      ],

  prov_wifi(from)::
      [
        {
          "type": "shell",
          "inline": [
            "test -z \"{{user `wifi_password`}}\" || wpa_passphrase \"{{user `wifi_name`}}\" \"{{user `wifi_password`}}\" | sed -e 's/#.*$//' -e '/^$/d' >> /etc/wpa_supplicant/wpa_supplicant.conf"
          ]
        },
      ],

  prov_aptinst(pkgs)::
      [
        {
          type: "shell",
          inline: [
            "apt-get update -y; DEBIAN_FRONTEND=noninteractive apt-get install -y " + std.join(' ', pkgs)
          ]
        },
      ],

//  prov_makecustompkgs()::
//      [
//        {
//          type: "shell-local",
//          inline: [
//            "test -d pkgbuilder || git clone https://github.com/ncabatoff/pkgbuilder",
//            "cd pkgbuilder",
//            "go get github.com/hashicorp/go-getter/cmd/go-getter",
//            "make packages",
//          ],
//        },
//      ],

  prov_custompkgs(from, arches)::
      [{type: "file", generated: true, source: from+a, destination: a} for a in arches],

  prov_prometheus(hosts)::
      [
        {
          "type": "shell-local",
          "inline": [
            "cat - > prometheus.yml <<EOF\n" + std.manifestYamlDoc(
            {
              global: {
                scrape_interval: "15s",
              },

              scrape_configs: [
                {
                  job_name: "prometheus",
                  static_configs: [
                    {
                      targets: ['localhost:9090'],
                    },
                  ],
                },
                {
                  job_name: "node",
                  static_configs: [
                    {
                      targets: [h + ":9100" for h in hosts] + ['localhost:9100'],
                    },
                  ],
                },
                {
                  job_name: "consul-servers",
                  static_configs: [
                    {
                      targets: [h + ":8500" for h in hosts],
                    },
                  ],
                  metrics_path: "/v1/agent/metrics",
                  params: {
                    format: ["prometheus"],
                  },
                },
                {
                  job_name: "nomad-servers",
                  static_configs: [
                    {
                      targets: [h + ":4646" for h in hosts],
                    },
                  ],
                  metrics_path: "/v1/metrics",
                  params: {
                    format: ["prometheus"],
                  },
                },
                {
                  job_name: "consul-services",
                  consul_sd_configs: [
                    {
                      server: "localhost:8500",
                    },
                  ],
                  relabel_configs: [
                    {
                      source_labels: ["__meta_consul_tags"],
                      regex: ".*,prom,.*",
                      action: "keep",
                    },
                    {
                      source_labels: ["__meta_consul_service"],
                      target_label: "job",
                    },
                  ],
                },
                {
                  job_name: "nomad-clients",
                  consul_sd_configs: [
                    {
                      server: "localhost:8500",
                      services: ['nomad-client'],
                    },
                  ],
                  metrics_path: "/v1/metrics",
                  params: {
                    format: ["prometheus"],
                  },
                  relabel_configs: [
                    {
                      source_labels: ["__meta_consul_tags"],
                      regex: "(.*)http(.*)",
                      action: "keep",
                    },
                  ],
                },
              ],
            }) + "\nEOF\n"
          ]
        },
        {
          type: "shell",
          inline: ["mkdir -p /opt/prometheus/config/"],
        },
        {
          type: "file",
          generated: true,
          source: "prometheus.yml",
          destination: "/opt/prometheus/config/",
        },
      ],

  prov_prometheus_register()::
      [
        {
          "type": "shell-local",
          "inline": [
            "cat - > prometheus.json <<EOF\n" + std.manifestJsonEx(
            {
                "service": {
                  "id": "prometheus",   // TODO make unique
                  "name": "prometheus",
                  "tags": ["primary"],  // TODO make prom-discoverable
                  "port": 9090,
                  "enable_tag_override": false,
                  "checks": [
                    {
                        "id": "api",
                        "name": "HTTP API on port 9090",
                        "http": "http://localhost:9090/metrics",
                        // "tls_skip_verify": true,
                        "method": "GET",
                        // "header": {"x-foo":["bar", "baz"]},
                        "interval": "10s",
                        "timeout": "1s"
                    }
                  ],
                }
            }, "  ") + "\nEOF\n"
          ]
        },
        {
          type: "file",
          generated: true,
          source: "prometheus.json",
          destination: "/opt/consul/config/prometheus.json",
        },
      ],
}
