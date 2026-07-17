FROM python:3.11-slim

RUN pip install --no-cache-dir \
    streamlit==1.39.0 \
    scikit-learn==1.5.2 \
    joblib==1.4.2 \
    pandas==2.2.3

WORKDIR /app
EXPOSE 8501

CMD ["streamlit", "run", "streamlit_app.py", "--server.port=8501", "--server.address=0.0.0.0"]
