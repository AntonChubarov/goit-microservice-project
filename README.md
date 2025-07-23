# Мікросервісний проєкт

Це репозиторій для навчального проєкту в межах курсу "DevOps CI/CD".

## Вимоги до середовища

- Операційна система Linux
- Git

## Завантаження проекту

1. Склонуйте репозиторій:
```shell
git clone https://github.com/AntonChubarov/goit-microservice-project.git
```
2. Перейдіть у папку проекту:
```shell
cd goit-microservice-project
```

## Встановлення інструментів для розробки
1. Перемкніться на гілку `lesson-3`:
```shell
git checkout lesson-3
```
2. Зробіть скрипт виконуваним:
```shell
chmod u+x install_dev_tools.sh
```
3. Запустіть скрипт:
```shell
./install_dev_tools.sh
```

## Збирання та запуск тестового проекту
1. Перемкніться на гілку `lesson-4`:
```shell
git checkout lesson-4
```

2. Зберіть та запустіть проект за допомогою docker compose:
```shell
docker compose up -d --build
```

3. Перевірте чи працюе Django-сервер відкривши сторінку [localhost/admin](http://localhost/admin) у браузері.

4. Перевірте чи Django-сервер має з'єднання з базою даних відкривши сторінку [localhost/db-check](http://localhost/db-check) у браузері.
