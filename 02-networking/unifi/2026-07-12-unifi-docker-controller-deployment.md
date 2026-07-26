# UniFi Docker Controller Deployment

## Objective

Replace the unstable Windows UniFi Network Server installation with a containerized deployment on `ubuntu-devops01`.

## Target Host

- Host: ubuntu-devops01
- Address: 192.168.1.114
- Platform: Docker Compose
- Application container: LinuxServer UniFi Network Application
- Database container: MongoDB

## Initial Validation

```bash
hostname
hostname -I
sudo systemctl status docker --no-pager
docker compose version
lscpu | grep -i avx


##################################################
## Environment Configuration

The UniFi deployment separates secrets from the Docker Compose file by using a `.env` file.

Benefits:

- Easier password rotation
- Cleaner compose.yaml
- Prevents hard-coded credentials
- Simplifies future Git management

MongoDB is initialized using `config/init-mongo.sh`, which creates the dedicated `unifi` database user used by the UniFi Network Application.
