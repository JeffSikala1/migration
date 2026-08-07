#!/opt/rh/rh-python36/root/bin/python3

import csv
import os
import datetime
import coloredlogs, logging
import pandas as pd

file_path = "/app/certificates_exp_checking_scripts/certificates/"
input_files = [file_path + 'SERVERCERTS.csv', file_path + 'CERT.csv', file_path +  'PROD.csv']
output_file1 = open(file_path + "EXPIRING_90_60_30.txt","w")
output_file2 = open(file_path + "EXPIRING_90_60_30.csv", "w")
output_file3 = open(file_path + "SERVERCERTS_ordered.csv","w")
output_file4 = open(file_path + "CERT_ordered.csv","w")
output_file5 = open(file_path + "PROD_ordered.csv","w")

today = datetime.date.today()
logger = logging.getLogger('certificate_check')
handler = logging.FileHandler('/var/log/messages')
handler.addFilter(coloredlogs.HostNameFilter())
formatter = coloredlogs.ColoredFormatter('%(asctime)s %(hostname)s %(message)s', "%b %a %H:%M:%S")
handler.setFormatter(formatter)
logger.addHandler(handler)

expired = 0 #Initialize cert expiration flag to false

# Write Column Headers to Text Report
column_headers_file1 = ('{0:16} {1:36} {2:36} {3:24} {4:1}'.format("Environment","Service Account Name","ShortPersonGUID (same as CN)","Certificate Expiration","Days Until Expired"))
output_file1.writelines(column_headers_file1)
output_file1.write("\n")
file_path + "CERT_ordered.csv"
# Write Column Headers to EXPIRING_90_60_30.csv
column_headers_output_files = ("Environment", ",", "Service Account Name", ",", "ShortPersonGUID (same as CN)", ",", "Certificate Expiration", ",", "Days Until Expired")
output_file2.writelines(column_headers_output_files)
output_file2.write(" \n")

# Collect all certs expiring within the 90/60/30 window here, across ALL input files,
# so we can sort them together (soonest-to-expire first) before writing any output.
expiring_rows = []

for i in input_files:

  df=pd.read_csv(i, sep=',')  #Read CSV input_files in as a Pandas Data Frame
  df['Certificate Expiration']=pd.to_datetime(df['Certificate Expiration']) #Change expiration dates to date time objects
  df=df.sort_values(by=['Certificate Expiration'])  #Sort data frame by expiration date

  if i == file_path + 'SERVERCERTS.csv':
    env = 'SERVER'
  elif i == file_path + 'CERT.csv':
    env = 'CERT'
  elif i == file_path + 'PROD.csv':
    env = 'PROD'

  for index, row in df.iterrows():

    cert_exp_datetime = row['Certificate Expiration']
    delta = cert_exp_datetime.date() - today

    if delta.days <= 90:
      logger.warning('Conexus_CERTIFICATE-EXPIRING: Check by cron found Certificate(s) that are EXPIRING')
      expiring_rows.append({
        'env': env,
        'name': row['Service Account Name'],
        'guid': row['ShortPersonGUID (same as CN)'],
        'exp_date': cert_exp_datetime,
        'days': delta.days
      })
      expired = 1 #Set cert exipration flag to true

    # Writing to SERVERCERTS_ordered.csv
    if i == file_path + 'SERVERCERTS.csv':
      L = ((str(row['Certificate Expiration'].strftime('%m/%d/%Y')),",",row['Service Account Name'],",",row['ShortPersonGUID (same as CN)']))
      output_file3.writelines(L)
      output_file3.write("\n")
    # Writing to CERT_ordered.csv
    if i == file_path + 'CERT.csv':
      L = ((str(row['Certificate Expiration'].strftime('%m/%d/%Y')),",",row['Service Account Name'],",",row['ShortPersonGUID (same as CN)']))
      output_file4.writelines(L)
      output_file4.write("\n")
    #Wrting to PROD_ordered.csv
    elif i == file_path + 'PROD.csv':
      L = ((str(row['Certificate Expiration'].strftime('%m/%d/%Y')),",",row['Service Account Name'],",",row['ShortPersonGUID (same as CN)']))
      output_file5.writelines(L)
      output_file5.write("\n")

# Sort the combined list of expiring certs across ALL environments by expiration date,
# soonest first, then write it out to the report files.
expiring_rows.sort(key=lambda r: r['exp_date'])

for r in expiring_rows:
  exp_str = str(r['exp_date'].strftime('%m/%d/%Y'))
  text_line = ('{0:16} {1:36} {2:36} {3:24} {4:1}'.format(r['env'], r['name'], r['guid'], exp_str, r['days']))
  csv_line = (r['env'], ",", r['name'], ",", r['guid'], ",", exp_str, ",", str(r['days']))
  output_file1.writelines(text_line)
  output_file1.write("\n")
  output_file2.writelines(csv_line)
  output_file2.write("\n")

output_file1.close()
output_file2.close()
output_file3.close()
output_file4.close()
output_file5.close()

if expired == 0:
  logger.warning('Conexus_CERTIFICATE-EXPIRING_Check: Certificate Check by cron')
  os.remove(str(file_path + "EXPIRING_90_60_30.txt"))
  os.remove(str(file_path + "EXPIRING_90_60_30.csv"))