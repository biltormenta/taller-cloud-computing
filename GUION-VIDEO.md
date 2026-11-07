# Guion del video: pipeline CodePipeline -> EKS (Kubernetes)

Duracion sugerida: 6 a 8 minutos. Entregable segun la clase del 3 de nov: hacer un cambio en el codigo, ver que dispara el pipeline hasta terminar y probarlo en el navegador.

## Datos del montaje (para decirlos en el video)
- Repositorio: https://github.com/biltormenta/taller-cloud-computing (rama `main`)
- Pipeline: `taller-eks` (us-east-1) con 3 etapas: Source -> Build -> Deploy
- Registro de imagenes: ECR `taller-eks`
- Cluster: `cluster-taller` (EKS), nodegroup de 2 nodos
- Diferencia con la clase: antes el Deploy iba a ECS; ahora el Deploy ejecuta `kubectl apply` contra EKS (Deployment + Service tipo LoadBalancer).

## 1. Presentacion (30 s)
"Voy a mostrar un pipeline en AWS CodePipeline que, cada vez que hago un cambio en GitHub, construye la imagen Docker, la sube a ECR y la despliega en un cluster de Kubernetes en EKS."

## 2. Mostrar el repositorio en GitHub (1 min)
Abrir el repo y mostrar los archivos:
- `Dockerfile`: imagen base httpd y copia de `index.html`.
- `index.html`: la pagina que vamos a modificar.
- `k8s/app.yaml`: Deployment (2 replicas) y Service tipo LoadBalancer. Decir que `IMAGE_URI` se reemplaza en el build.
- `buildspec-build.yml` y `buildspec-deploy.yml`: los pasos de las etapas Build y Deploy.

## 3. Mostrar la infraestructura en AWS (1 min)
- EKS -> Clusters -> `cluster-taller` activo, pestana Compute con el nodegroup (2 nodos).
- ECR -> repositorio `taller-eks`.
- CodePipeline -> `taller-eks`: mostrar las 3 etapas (Source, Build, Deploy).

## 4. Hacer el cambio en el codigo (1 min)
En GitHub abrir `index.html`, editar (lapiz), cambiar `Version 1` por `Version 2` y hacer Commit directo a `main`.
Decir: "Este commit genera un evento push que GitHub notifica a AWS por la GitHub App y dispara el pipeline."

## 5. Ver el pipeline correr (2 a 3 min)
- Volver a CodePipeline y mostrar Source en verde, Build en curso (explicar: construye la imagen y la sube a ECR) y luego Deploy.
- Opcional: en ECR mostrar la nueva imagen con el tag del commit.
- Esperar a que las tres etapas queden en verde.

## 6. Comprobar en Kubernetes (1 min)
Abrir CloudShell y ejecutar:
```
aws eks update-kubeconfig --name cluster-taller --region us-east-1
kubectl get pods
kubectl get svc web-service
```
Mostrar 2 pods `1/1 Running` y el `EXTERNAL-IP` (dominio del balanceador).

## 7. Probar en el navegador (30 s)
Abrir `http://<EXTERNAL-IP>` (sin la "s") y mostrar que dice **Version 2**.

## 8. Cierre (20 s)
"Con un solo cambio en el codigo, el pipeline hizo todo el despliegue en EKS sin tocar AWS manualmente."

## Notas
- Si el navegador no abre la pagina, esperar 1 o 2 minutos: el DNS del balanceador tarda en propagarse.
- Si la red de la universidad bloquea el puerto, probar desde datos moviles o un sitio de pruebas HTTP.
