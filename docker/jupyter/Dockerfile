FROM python:3.11-slim

RUN pip install --no-cache-dir \
    jupyterlab==4.2.5 \
    matplotlib==3.9.2 \
    seaborn==0.13.2 \
    plotly==5.24.1

COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

WORKDIR /home/jovyan/work
EXPOSE 8888

CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--ServerApp.token="]
