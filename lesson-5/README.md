# Lesson 5 Terraform project

## Встановіть Terraform (якщо необхідно)

Використовуйте офіційний [Гайд з інсталяції](https://developer.hashicorp.com/terraform/install)

## Встановіть AWS CLI (якщо необхідно)

Використовуйте офіційний [Гайд з інсталяції](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

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

3. Перемкніться на гілку `lesson-5`:
```shell
git checkout lesson-5
```

4. Перейдіть у папку проекту:
```shell
cd lesson-5
```

5. Закоментуйте код у файлі ```backend.tf```.

6. Ініціалізуйте проект Terraform:
```shell
terraform init
```

7. Перевірте конфігурацію проекту Terraform:
```shell
terraform validate
```

8. Перевірте план розгортання проекту Terraform:
```shell
terraform plan
```

9. Розгорніть проект Terraform:
```shell
terraform apply
```

10. Розкоментуйте код у файлі ```backend.tf```.

11. Переконфыгуруйте проект Terraform:
```shell
terraform init -reconfigure
```
12. Повторіть команду розгортання проекту щоб додати стан у S3-бакет:
```shell
terraform apply
```

13. Після перевірки видаліть проект Terraform:
```shell
terraform destroy
```

14. Додатково - видаліть S3 бакет та талиці DynamoDB через консоль AWS.
