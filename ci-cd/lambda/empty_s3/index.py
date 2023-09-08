import boto3
import json
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    codepipeline = boto3.client('codepipeline')
    s3 = boto3.resource('s3')

    # Retrieve the bucket name from the input event
    user_parameters = json.loads(event['CodePipeline.job']['data']['actionConfiguration']['configuration']['UserParameters'])
    bucket_name = user_parameters.get('bucket_name')
    job_id = event['CodePipeline.job']['id']

    # Check if bucket_name is provided
    if not bucket_name:
        return {
            'statusCode': 400,
            'body': 'No bucket_name provided in the input.'
        }

    bucket = s3.Bucket(bucket_name)

    try:
        # Delete all objects in the bucket
        bucket.objects.all().delete()

        # Signal success to CodePipeline
        codepipeline.put_job_success_result(jobId=job_id)
    except ClientError as e:
        # Signal failure to CodePipeline
        print(f"Error emptying S3 bucket {bucket_name}: {e}")

        codepipeline.put_job_failure_result(
            jobId=job_id,
            failureDetails={
                'type': 'JobFailed',
                'message': f'Failed to empty bucket {bucket_name}. Exception: {e}'
            }
        )
