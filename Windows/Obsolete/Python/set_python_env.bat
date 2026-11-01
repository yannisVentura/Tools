echo "enter the Django manage.py path : "
read $PATH
cd $PATH
python -m pip install virtualenv
virtualenv venv
move venv ..
cd ..
venv activate
cd $PATH
python manage.py runserver