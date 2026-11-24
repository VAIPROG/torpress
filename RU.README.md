# Torpress

[English documentation](README.md)

Torpress запускает WordPress, MariaDB и onion-сервис Tor в отдельных контейнерах. Docker Compose не публикует порты на хосте. Чтобы открыть сайт, используйте [Tor Browser](https://www.torproject.org/).

## Установка из готовых образов

Понадобятся Docker с Compose версии 2.24.4 или новее, Git, Bash и OpenSSL. Выберите тег на странице [релизов](https://github.com/VAIPROG/torpress/releases). В примере используется `v1.0.0`. Выполняйте команды в одной сессии Bash.

```bash
release_tag=v1.0.0
git clone --branch "$release_tag" --single-branch https://github.com/VAIPROG/torpress.git
cd torpress
export TORPRESS_IMAGE_TAG="$release_tag"
compose=(docker compose -f compose.yaml -f compose.release.yaml)
"${compose[@]}" --profile onion pull
```

Compose скачает образы WordPress, MariaDB и Tor с одинаковым тегом из пространства имён `vaiprog` в Docker Hub. Для сборки из исходников используйте `docker compose --profile onion build` и замените массив `compose` на `compose=(docker compose)`.

### Создайте пароли базы и ключ для сессий

В образах нет готовых паролей. При первом запуске Compose подключает файлы из каталога `.secrets/` на вашем сервере.

| Файл | Для чего нужен |
| --- | --- |
| `.secrets/db_password` | Пароль пользователя MariaDB `wordpress`. MariaDB и WordPress читают один и тот же файл. |
| `.secrets/db_root_password` | Пароль пользователя MariaDB `root` для администрирования внутри контейнера БД. |
| `.secrets/wordpress_salt` | Секрет для подписи сессий и cookie WordPress. При входе его вводить не нужно. |

В каждом файле должна быть отдельная случайная строка из 64 шестнадцатеричных символов. Следующая команда создаёт недостающие файлы и сохраняет существующие.

```bash
(
    umask 077
    mkdir -p .secrets
    for secret in db_password db_root_password wordpress_salt; do
        if [[ ! -e ".secrets/$secret" ]]; then
            openssl rand -hex 32 > ".secrets/$secret"
        fi
    done
)
"${compose[@]}" up -d db wordpress
```

Ограничьте доступ к этим файлам и храните их резервную копию вместе с базой. Если секреты лежат в другом каталоге, задайте `TORPRESS_SECRETS_DIR` перед запуском Compose.

MariaDB применяет пароли из файлов при первой инициализации тома. Для существующей базы сначала поменяйте пароли учётных записей в самой MariaDB, затем обновите файлы и перезапустите сервисы. Простая замена файлов не меняет пароли в базе.

### Задайте пароль администратора WordPress

Сначала получите onion-адрес. Команда генерирует ключ с отключённой сетью Tor и записывает его в том Tor. Храните резервную копию этого тома, чтобы сохранить адрес сайта.

```bash
onion_host=$("${compose[@]}" --profile onion run --rm --no-deps tor torpress-onion-hostname)
```

Выберите название сайта, имя администратора и его email. Создайте отдельный пароль длиной не менее 20 байт в менеджере паролей. Введите его после приглашения. Bash передаст пароль через стандартный ввод без отображения на экране.

```bash
read -rsp 'Пароль администратора WordPress: ' admin_password
printf '\n' >&2
printf '%s' "$admin_password" |
    "${compose[@]}" exec -T --user www-data wordpress \
        php /usr/local/lib/torpress/install.php "$onion_host" \
        'Мой сайт' operator operator@example.org
unset admin_password
```

После сообщения `WordPress installed.` запустите Tor и откройте страницу входа в Tor Browser. Используйте выбранное имя администратора и пароль из менеджера паролей.

```bash
"${compose[@]}" --profile onion up -d tor
printf 'http://%s/wp-admin/\n' "$onion_host"
```

Веб-установка отключена. Для существующего сайта пропустите установку. Пароль можно сменить в профиле пользователя WordPress после входа.

Если вы потеряли пароль, сбросьте его через WP-CLI. Подставьте своё имя пользователя вместо `operator`. Команда выведет новый пароль в терминал. Запускайте её в приватной сессии и сохраните пароль в менеджере паролей.

```bash
"${compose[@]}" exec -T --user www-data wordpress \
    wp user reset-password operator --skip-email --show-password
```

## Обновление и перенос

- Перед обновлением сохраните базу, `wp-content`, ключ onion-сервиса и файлы с секретами.
- При обновлении из Docker Hub возьмите Compose-файлы нового релиза, задайте его тег в `TORPRESS_IMAGE_TAG` и скачайте все три образа. Проверьте дайджесты в заметках к релизу. Остановите Tor на время обновления и после запуска WordPress выполните `"${compose[@]}" exec --user www-data wordpress wp core update-db`. Затем снова запустите Tor.
- При переносе со старой одноконтейнерной версии импортируйте логический дамп сайта в базу `wordpress` на новом томе. Проверьте префикс таблиц. По умолчанию Torpress использует `wp_`. Восстановите `wp-content` с владельцем `www-data`.
- Чтобы сохранить прежний onion-адрес, восстановите каталог `/var/lib/tor/hidden_service` в томе Tor. У каталога должны быть владелец `debian-tor` и права `0700`. Проверьте адрес до запуска Tor и при необходимости обновите параметры `home` и `siteurl` через WP-CLI.
- Устанавливайте обновления плагинов и тем из проверенных пакетов в `wp-content`. Редактор файлов и автоматические обновления в WordPress отключены.

## Безопасность и проверка

MariaDB доступна в закрытой сети Compose. Apache блокирует публичный XML-RPC, TRACE и запуск PHP в каталоге загрузок. WordPress не имеет прямого доступа в интернет. Известные ограничения базовых образов указаны в [PR с обновлением стека](https://github.com/VAIPROG/torpress/pull/1).

После локальной сборки `bash tests/smoke.sh` проверяет установку, отказ при слабых секретах, настройки Apache и генерацию onion-адреса. Тест использует временные тома и отключает сеть Tor.

## Публикация для сопровождающих

Workflow публикует образы для Linux amd64 и arm64 по тегу вида `v1.0.0` на коммите из `master`. Создайте три репозитория в Docker Hub и задайте переменную `DOCKERHUB_USERNAME` и секрет `DOCKERHUB_TOKEN` с правами Read & Write. Для обновления описаний используйте `DOCKERHUB_OVERVIEW_TOKEN` с правами Read, Write & Delete. Если у основного токена уже есть эти права, отдельный токен для описаний можно пропустить. Секреты сайта создаются на сервере при установке. [Подробности о публикации](README.md#publish-a-release)
