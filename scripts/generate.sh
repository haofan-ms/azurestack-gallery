#!/bin/bash

mkdir -p _out
_out/encoder ./kubernetes/template/DeploymentTemplates/script.sh > _out/customdata-k8s.txt
_out/encoder ./registry/Scripts/script.sh > _out/customdata-registry.txt
