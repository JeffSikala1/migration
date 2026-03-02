kubectl apply -f ./nlb/deployenvsubst-dev.yaml
kubectl apply -f ./apache/apache-config-dev.yaml
kubectl apply -f ./avapache/avapache-config-dev.yaml
kubectl apply -f ./wso2/wso2mi-config-dev.yaml
kubectl apply -f ./jboss/jboss-config-dev.yaml
kubectl apply -f ./apache/httpd-ingress-dev.yaml
kubectl apply -f ./wso2/wso2mi-ingress-dev.yaml
kubectl apply -f ./efs_mounts/efs-attachmentsVolumeNClaim-dev.yaml
kubectl apply -f ./efs_mounts/efs-dataVolumeNClaim-dev.yaml
kubectl apply -f ./efs_mounts/efs-rejectVolumeNClaim-dev.yaml
kubectl apply -f ./efs_mounts/efs-reportsVolumeNClaim-dev.yaml
kubectl apply -f ./efs_mounts/efs-databaseVolumeNClaim-dev.yaml



