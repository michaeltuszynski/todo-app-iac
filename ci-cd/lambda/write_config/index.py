import boto3
import json
from botocore.exceptions import ClientError

codepipeline = boto3.client("codepipeline")
s3 = boto3.resource("s3")


def put_config_to_s3(bucket_name, environment_variables):
    data = json.dumps(environment_variables)

    s3.Object(bucket_name, "config.json").put(Body=str(data))


def lambda_handler(event, context):
    # Extract the Job ID from the Lambda action
    job_id = event["CodePipeline.job"]["id"]

    # S3 Bucket name from the environment variable
    user_parameters = json.loads(
        event["CodePipeline.job"]["data"]["actionConfiguration"]["configuration"][
            "UserParameters"
        ]
    )
    bucket_name = user_parameters.get("bucket_name")
    environment_variables = user_parameters.get("environment_variables")

    try:
        # Put config.json to the specified S3 bucket
        put_config_to_s3(bucket_name, environment_variables)

        # Signal success to CodePipeline
        codepipeline.put_job_success_result(jobId=job_id)
    except ClientError as e:
        print(f"Error putting config.json to S3 bucket {bucket_name}: {e}")

        # Signal failure to CodePipeline
        codepipeline.put_job_failure_result(
            jobId=job_id,
            failureDetails={
                "type": "JobFailed",
                "message": f"Failed to put config.json to S3: {e}",
            },
        )
