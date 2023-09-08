import boto3
import json
from botocore.exceptions import ClientError

codepipeline = boto3.client('codepipeline')
cloudfront = boto3.client('cloudfront')

def create_invalidation(distribution_id, paths):
    cloudfront.create_invalidation(
        DistributionId=distribution_id,
        InvalidationBatch={
            'Paths': {
                'Quantity': len(paths),
                'Items': paths
            },
            'CallerReference': 'codepipeline-invalidation'
        }
    )

def lambda_handler(event, context):
    # Extract the Job ID from the Lambda action
    job_id = event['CodePipeline.job']['id']

    user_parameters = json.loads(event['CodePipeline.job']['data']['actionConfiguration']['configuration']['UserParameters'])
    distribution_id = user_parameters.get('distribution_id')

    try:
        # Create invalidation for the entire site
        create_invalidation(distribution_id, ['/*'])

        # Signal success to CodePipeline
        codepipeline.put_job_success_result(jobId=job_id)
    except ClientError as e:
        print(f"Error creating invalidation for CloudFront distribution {distribution_id}: {e}")

        # Signal failure to CodePipeline
        codepipeline.put_job_failure_result(
            jobId=job_id,
            failureDetails={
                'type': 'JobFailed',
                'message': f"Failed to create invalidation: {e}"
            }
        )
