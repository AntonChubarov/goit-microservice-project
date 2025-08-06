# Lesson 5 Terraform project

## Вимоги до середовища

- Операційна система Linux
- Git
- Docker
- AWS CLI
- Terraform
- Helm
- kubectl

Переконайтеся що автентифікаційні дані для Вашого AWS аккаунту налаштовані у вашій системі.

## Розгортання проекту

1. Склонуйте репозиторій:
```shell
git clone https://github.com/AntonChubarov/goit-microservice-project.git
```

2. Перейдіть у папку проекту:
```shell
cd goit-microservice-project
```

3. Перемкніться на гілку `lesson-8-9`:
```shell
git checkout lesson-8-9
```

4. Перейдіть у папку проекту:
```shell
cd lesson-8-9
```

6. Розгорніть проект:
```shell
sh scripts/deploy.sh
```

7. Перевірте що застосунок працює: Перейдіть за посиланням `http://<Service hostname>/db-check` - повинно бути отримане повідомлення `{"status": "ok"}`, або перейдіть за посиланням `http://<Service hostname>/admin` - повинна відобразитись дефолтна адмін-сторінка Django-сервісу. Service hostname буде виведено в кінці виконання скрипта.

   Примітка: сервіс може стати доступним на посиланням не миттєво після завершення роботи скрипта.

8. Налаштуйте конфігурацію для віддаленого керування кластером Kubernetes:
```shell
sh scripts/aws_kubeconfig.sh
```

9. Перегляньте список подів:
```shell
kubectl get pods
```

10. Перевірте логи подів:
```shell
kubectl logs -f <pod_name>
```

11. Альтернативно - скористайтесь інструментом `k9s`.

12. Видаліть проект:
```shell
sh scripts/destroy.sh
```