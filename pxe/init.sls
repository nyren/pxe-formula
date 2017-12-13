# Include :download:`map file <map.jinja>` of OS-specific package names and
# file paths. Values can be overridden using Pillar.
{%- from "pxe/map.jinja" import dnsmasq, syslinux with context %}
{%- set pxe = pillar.get('pxe', {}) %}
{#- FIXME: generic lookup of settings with default values #}
{%- set tftp_root = pxe.get('tftp_root', '/srv/pxe') %}

dnsmasq_conf:
  file.managed:
    - name: {{ dnsmasq.dnsmasq_conf }}
    - source: {{ 'salt://pxe/files/dnsmasq.conf.jinja' }}
    - user: root
    - group: root
    - mode: 644
    - template: jinja

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

tftp_root:
  file.directory:
    - name: {{ tftp_root }}
    - user: root
    - group: root
    - dir_mode: 755

{%- for file_name, file_source in syslinux.syslinux_files|dictsort %}
pxe_loader_{{ file_name }}:
  file.managed:
    - name: '{{ tftp_root }}/{{ file_name }}'
    - user: {{ dnsmasq.dnsmasq_user }}
    - group: {{ dnsmasq.dnsmasq_group }}
    - mode: 644
    - source: '{{ syslinux.syslinux_dir }}/{{ file_source }}'
    - require:
      - pkg: syslinux
      - file: tftp_root
{%- endfor %}

pxe_config_dir:
  file.directory:
    - name: {{ tftp_root }}/pxelinux.cfg
    - user: {{ dnsmasq.dnsmasq_user }}
    - group: {{ dnsmasq.dnsmasq_group }}
    - dir_mode: 755
    - require:
      - file: tftp_root

{%- for name, data in pxe.get('hosts', {})|dictsort %}
{% set hw_file = "01-%s"|format(data['hw'].lower().replace(':', '-')) %}
{% set os_name = data.get('os', 'centos-7') %}
{% set os_type = pxe['os'].get('type', 'linux') %}
pxe_config_host_{{ name }}:
  file.managed:
    - name: {{ tftp_root }}/pxelinux.cfg/{{ hw_file }}
    - user: {{ dnsmasq.dnsmasq_user }}
    - group: {{ dnsmasq.dnsmasq_group }}
    - mode: 644
    - template: jinja
    - source: {{ "salt://pxe/files/pxelinux_config_%s.jinja"|format(os_type) }}
    - context:
      boot_name: {{ os_name }}
      boot_options: {{ pxe['os'][os_name]['options'] }}
    - require:
      - file: pxe_config_dir
{%- endfor %}

pxe_images_dir:
  file.directory:
    - name: {{ tftp_root }}/images
    - user: {{ dnsmasq.dnsmasq_user }}
    - group: {{ dnsmasq.dnsmasq_group }}
    - dir_mode: 755
    - require:
      - file: tftp_root

{%- for name, data in pxe.get('os', {})|dictsort %}
os_{{ name }}_dir:
  file.directory:
    - name: {{ tftp_root }}/images/{{ name }}
    - user: {{ dnsmasq.dnsmasq_user }}
    - group: {{ dnsmasq.dnsmasq_group }}
    - dir_mode: 755
    - require:
      - file: pxe_images_dir
{%-   for file_name, file_source in data.get('files', {})|dictsort %}
os_{{ name }}_{{ file_name }}:
  file.managed:
    - name: {{ tftp_root }}/images/{{ name }}/{{ file_name }}
    - user: {{ dnsmasq.dnsmasq_user }}
    - group: {{ dnsmasq.dnsmasq_group }}
    - mode: 644
    - source: {{ file_source }}
    - skip_verify: True {# FIXME: Replace with source_hash #}
    - require:
      - file: os_{{ name }}_dir
{%-   endfor %}
{%- endfor %}

