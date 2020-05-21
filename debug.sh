export USER=postgres 
export PASS=postgres
export HOST=localhost 
export DATABASE=bex_dev
export PORT=8880 
export DATABASE_URL=ecto://$USER:$PASS@$HOST/$DATABASE 
export SECRET_KEY_BASE=1irqCrVrCD5yoTlarJAmHHVMLFKKvND8OJhkFYuT3kOf1Ke1LVAmHdUyI7/+HfoS 
export BexAdmin=dashboard 
export BexChat=false

iex -S mix phx.server 
