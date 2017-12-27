{#- OS-specifics -#}
{%- from "pxe/map.jinja" import dnsmasq, syslinux with context %}

{#- Pillar data -#}
{%- set listen_address      = salt['pillar.get']('pxe:listen_address', '127.0.0.1') -%}
{%- set domain_name         = salt['pillar.get']('pxe:domain_name') -%}
{%- set domain_name_servers = salt['pillar.get']('pxe:domain_name_servers', []) -%}
{%- set default_os          = salt['pillar.get']('pxe:default_os') -%}
{%- set os                  = salt['pillar.get']('pxe:os', {}) -%}
{%- set subnets             = salt['pillar.get']('pxe:subnets', {}) -%}
{%- set hosts               = salt['pillar.get']('pxe:hosts', {}) -%}
{%- set tftp_root_path      = salt['pillar.get']('pxe:tftp_root', '/srv/pxe') -%}
{%- set tftp_boot_path      = salt['pillar.get']('pxe:tftp_boot', '/pxelinux.0') -%}
{%- set pxe_config_dir      = salt['pillar.get']('pxe:pxe_config_dir', 'pxelinux.cfg') -%}
{%- set pxe_images_dir      = salt['pillar.get']('pxe:pxe_images_dir', 'images') -%}

{# Internal data #}
{%- set _pxe_config_dir_path = salt['file.join'](tftp_root_path, pxe_config_dir) %}
{%- set _pxe_images_dir_path = salt['file.join'](tftp_root_path, pxe_images_dir) %}
{%- set _pxe_config_host_files = {} %}

{#- States -#}
dnsmasq_conf:
  file.managed:
    - name: {{ dnsmasq.dnsmasq_conf }}
    - source: {{ 'salt://pxe/files/dnsmasq.conf.jinja' }}
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - context:
      listen_address: {{ listen_address }}
      tftp_root_path: {{ tftp_root_path }}
      tftp_boot_path: {{ tftp_boot_path }}
      domain_name: {{ domain_name }}
      domain_name_servers: {{ domain_name_servers }}
      subnets: {{ subnets }}
      hosts: {{ hosts }}

dnsmasq:
  pkg.installed:
    - name: {{ dnsmasq.package }}
  service.running:
    - name: {{ dnsmasq.service }}
    - enable: True
    - require:
      - pkg: dnsmasq
      - file: pxe_loader_pxelinux.0
    - watch:
      - file: dnsmasq_conf

syslinux:
  pkg.installed:
    - name: {{ syslinux.package }}

# TFTP-root directory
tftp_root:
  file.directory:
    - name: {{ tftp_root_path }}
    - user: root
    - group: root
    - dir_mode: 755

# PXE binaries
{%- for file_name, file_source in syslinux.syslinux_files|dictsort %}
pxe_loader_{{ file_name }}:
  file.managed:
    - name: '{{ tftp_root_path }}/{{ file_name }}'
    - user: {{ dnsmasq.dnsmasq_user }}
    - group: {{ dnsmasq.dnsmasq_group }}
    - mode: 644
    - source: '{{ syslinux.syslinux_dir }}/{{ file_source }}'
    - require:
      - pkg: syslinux
      - file: tftp_root
{%- endfor %}

# Directory inside TFTP-root containing PXE host config files
pxe_config_dir:
  file.directory:
    - name: {{ _pxe_config_dir_path }}
    - user: {{ dnsmasq.dnsmasq_user }}
    - group: {{ dnsmasq.dnsmasq_group }}
    - dir_mode: 755
    - require:
      - file: tftp_root

# Add PXE host config files based on MAC address
{%- for name, data in hosts|dictsort %}
{%-   set config_path = "%s/01-%s"|format(_pxe_config_dir_path, data['hw'].lower().replace(':', '-')) %}
{%-   set enable = data.get('enable', True) %}
{%-   set os_name = data.get('os', default_os) %}
{%-   if enable and os_name %}
{%-     do _pxe_config_host_files.update({config_path: name}) %}
{%-     set os_kernel = os[os_name]['kernel'] %}
{%-     set os_options = os[os_name]['options'] %}
pxe_config_add_host_{{ name }}:
  file.managed:
    - name: {{ config_path }}
    - user: {{ dnsmasq.dnsmasq_user }}
    - group: {{ dnsmasq.dnsmasq_group }}
    - mode: 644
    - template: jinja
    - source: {{ "salt://pxe/files/pxelinux_config_%s.jinja"|format(os_kernel) }}
    - context:
      boot_name: {{ os_name }}
      boot_options: {{ os_options }}
    - require:
      - file: pxe_config_dir
{%-   endif %}
{%- endfor %}

# Remove obsolete PXE host config files
{%- for path in salt['file.find'](_pxe_config_dir_path, type='f', maxdepth=1) %}
{%-   if path not in _pxe_config_host_files %}
pxe_config_remove_host_{{ salt['file.basename'](path) }}:
  file.absent:
    - name: '{{ path }}'
{%-   endif %}
{%- endfor %}

# Directory inside TFTP-root containing boot images for configured OS
pxe_images_dir:
  file.directory:
    - name: {{ _pxe_images_dir_path }}
    - user: {{ dnsmasq.dnsmasq_user }}
    - group: {{ dnsmasq.dnsmasq_group }}
    - dir_mode: 755
    - require:
      - file: tftp_root

# Create OS directory and download boot images
{%- for name, data in os|dictsort %}
{%-   set os_dir_path = salt['file.join'](_pxe_images_dir_path, name) %}
os_{{ name }}_dir:
  file.directory:
    - name: {{ os_dir_path }}
    - user: {{ dnsmasq.dnsmasq_user }}
    - group: {{ dnsmasq.dnsmasq_group }}
    - dir_mode: 755
    - require:
      - file: pxe_images_dir
{%-   for file_name, data in data.get('files', {})|dictsort %}
{%-     set file_hash = '' %}
{%-     if data is string %}
{%-       set file_source = data %}
{%-     else %}
{%-       set file_source = data['source'] %}
{%-       set file_hash   = data.get('hash', '') %}
{%-     endif %}
os_{{ name }}_{{ file_name }}:
  file.managed:
    - name: {{ os_dir_path }}/{{ file_name }}
    - user: {{ dnsmasq.dnsmasq_user }}
    - group: {{ dnsmasq.dnsmasq_group }}
    - mode: 644
    - source: {{ file_source }}
    - source_hash: {{ file_hash }}
    - require:
      - file: os_{{ name }}_dir
{%-   endfor %}
{%- endfor %}
