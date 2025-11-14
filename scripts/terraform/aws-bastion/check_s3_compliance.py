#!/usr/bin/env python3

import boto3
from botocore.exceptions import ClientError

def main():
    s3 = boto3.client('s3')

    try:
        # 1) List all buckets
        response = s3.list_buckets()
        buckets = response.get('Buckets', [])
        if not buckets:
            print("No buckets found.")
            return

        for bucket_info in buckets:
            bucket_name = bucket_info['Name']
            print(f"\n=== Checking Bucket: {bucket_name} ===")

            # 2) GetBucketAcl
            try:
                acl_response = s3.get_bucket_acl(Bucket=bucket_name)
                print("ACL Grantees:", acl_response['Grants'])
            except ClientError as e:
                print("Error getting ACL:", e)

            # 3) GetBucketWebsite
            try:
                website_response = s3.get_bucket_website(Bucket=bucket_name)
                print("Website configuration:", website_response)
            except ClientError as e:
                if e.response['Error']['Code'] == 'NoSuchWebsiteConfiguration':
                    print("No website configuration (GOOD if you want it disabled).")
                else:
                    print("Error getting website:", e)

            # 4) GetBucketPolicy
            try:
                policy_response = s3.get_bucket_policy(Bucket=bucket_name)
                policy_str = policy_response['Policy']
                print("Bucket policy:", policy_str)
            except ClientError as e:
                if e.response['Error']['Code'] == 'NoSuchBucketPolicy':
                    print("No bucket policy attached (often OK).")
                else:
                    print("Error getting policy:", e)

            # TODO: Insert your compliance checks here
            # For example, parse the ACL or policy JSON to see if there's public access.
            # Or ensure website config is absent if your policy is "no static hosting."

    except ClientError as e:
        print(f"Error listing buckets: {e}")

if __name__ == "__main__":
    main()