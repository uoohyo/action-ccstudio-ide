#!/bin/bash

eclipse -noSplash -data /tmp/workspace -application com.ti.ccstudio.apps.projectImport -ccs.location "$1"
eclipse -noSplash -data /tmp/workspace -application com.ti.ccstudio.apps.projectBuild -ccs.projects "$1" -ccs.configuration "$2"